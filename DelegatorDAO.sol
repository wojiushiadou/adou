// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
import "StakingInterface.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract DelegatorDAO is AccessControl{
    using SafeMath for uint256;

    //成员角色权限
    bytes32 private MEMBER;
    //预编译地址
    address private constant precompileAddress = 0x0000000000000000000000000000000000000800;
    //预编译接口对象
    ParachainStaking private staking;
    //抵押总量
    uint256 private totalStake;
    //提名成员抵押量
    mapping(address => uint256) private memberStakes;
    //提名成员赎回量
    mapping(address => uint256) private memberRedeems;

    //节点配置信息
    struct NodeConfig{
        uint techProportion;//技术服务比例
        uint fundsDownLimit;//节点投资抵押最低下限
        uint investorUpLimit;//投资人数上限
        address collatorAddr;//有效收集人地址
        uint perInvestDownLimit;//每人次投资抵押下限
        uint voterProportion;//投票参与人数比例
        uint rewardDownLimit;//最低分配奖励额度
        address governanceAdmin;//治理管理人
        uint256 scheduleTime;//网络解绑时间
    }
    NodeConfig private nodeConfig;

    //赎回参数配置
    struct RedeemConfig{
        uint bondLess;//计划赎回解绑数
        address bondLessAddr;//计划赎回解绑地址
        uint256 bondLessTime;//计划赎回时间
    }
    RedeemConfig private redeemConfig;

    //节点启动时间,时间戳
    uint256 private nodeStartDate;
    //技术服务费最低比例限制
    uint constant private techDownLimit = 20;
    //投票参与人数最低比例限制
    uint constant private voterDownLimit = 51;
    //治理开启标记
    bool private governanceFlag = false;
    //提名成员人数
    uint private memberTotal = 0;
    //实际提名成员人数
    uint private memberReal = 0;
    //提名成员地址
    mapping(uint => address) private memberAddrs;
    //提名成员奖励
    mapping(address => uint256) private memberRewards;
    //总奖励
    uint256 private totalReward = 0;
    //待领取奖励
    uint256 private pendingReward = 0;
    //提案编号,顺序递增
    uint private currentNumber = 0;
    //计划解散时间
    uint256 private leaveTime;
    //提案对象
    struct GovernanceInfo{
        uint number; //提案编号
        uint256 startDate;//治理开始时间 
        uint256 endDate;//治理结束时间
        uint uintValue;//治理更新数值
        address addrValue;//治理更新地址
        uint totalVoter;//应投票总人数,一般为提名人总人数
        uint approveVoter;//赞成票
        uint opposeVoter;//反对票
        bool success; //治理投票标记 true成功 false失败
    }
    //提案信息,governanceInfos[type]=info,type表示提案类型,info表示提案对象
    //提案类型:0技术服务比例 1节点投资抵押最低下限 2投资人数上限 3有效收集人地址 4每人次投资抵押下限 5投票参与人数最低比例 6最低分配奖励额度 7治理管理人 8节点解散
    mapping(uint => GovernanceInfo) private governanceInfos;
    //提案投票governanceVotes[number][adr]=state,number表示提案编号,adr表示投票人,state表示投票状态0未投票 1赞成 2反对
    mapping(uint => mapping (address => uint)) private governanceVotes;
    //合约sudo地址
    address private ownerAddress;

    constructor(uint _techProportion
                ,uint _fundsDownLimit
                ,uint _investorUpLimit
                ,address _collatorAddr
                ,uint _perInvestDownLimit
                ,uint _voterProportion
                ,uint256 _nodeStartDate
                ,uint256 _rewardDownLimit
                ,address _techRewardAddr
                ,uint256 _scheduleTime) {
        nodeConfig.techProportion = _techProportion;
        nodeConfig.fundsDownLimit = _fundsDownLimit;
        nodeConfig.investorUpLimit = _investorUpLimit;
        nodeConfig.collatorAddr =  _collatorAddr;
        nodeConfig.perInvestDownLimit =  _perInvestDownLimit;
        nodeConfig.voterProportion =  _voterProportion;
        nodeConfig.rewardDownLimit = _rewardDownLimit;
        nodeStartDate = _nodeStartDate;
        nodeConfig.scheduleTime =  _scheduleTime;
        nodeConfig.governanceAdmin = msg.sender;
        ownerAddress = msg.sender;
        staking = ParachainStaking(precompileAddress);
        //技术服务奖励地址
        MEMBER = bytes32(uint256(uint160(address(this))) << 96);
        memberAddrs[memberTotal] = _techRewardAddr;
        memberTotal = memberTotal.add(1);
        _setupRole(MEMBER, _techRewardAddr);
    }

    modifier isGovernance() { 
        require(msg.sender == nodeConfig.governanceAdmin,'Not gov management!');
        require(governanceFlag,'Node not started!');
        _;
    }

    modifier isSchedule() { 
        require(msg.sender == ownerAddress,'Not management!');
        _;
    }

    modifier isOwner() { 
        require(msg.sender == ownerAddress,'Not management!');
        require(!governanceFlag,'Node started!');
        _;
    }

    fallback () external payable{}

    receive () external payable{}

    //sudo权限,开启治理后失效
    function setParameter(uint _techProportion
                ,uint _fundsDownLimit
                ,uint _investorUpLimit
                ,address _collatorAddr
                ,uint _perInvestDownLimit
                ,uint _voterProportion
                ,uint256 _nodeStartDate
                ,uint256 _rewardDownLimit
                ,uint256 _scheduleTime) public isOwner{
        require(!governanceFlag,'Node started!');
        require(_techProportion >= techDownLimit,'_techProportion is illegal!');
        require(_voterProportion >= voterDownLimit,'_voterProportion is illegal!');
        nodeConfig.techProportion = _techProportion;
        nodeConfig.fundsDownLimit = _fundsDownLimit;
        nodeConfig.investorUpLimit = _investorUpLimit;
        nodeConfig.collatorAddr =  _collatorAddr;
        nodeConfig.perInvestDownLimit =  _perInvestDownLimit;
        nodeConfig.voterProportion =  _voterProportion;
        nodeConfig.rewardDownLimit = _rewardDownLimit;
        nodeStartDate = _nodeStartDate;
        nodeConfig.scheduleTime =  _scheduleTime;
    }

    //治理开启
    function _setGovern(GovernanceInfo memory _info
                ,uint _uintValue
                ,address _addrValue
                ,uint256 _startDate
                ,uint256 _endDate) private returns (GovernanceInfo memory){
        require(_startDate > block.timestamp && _startDate < _endDate,'Date is illegal!');
        if(_info.number == 0 || _info.endDate < block.timestamp){
            currentNumber = currentNumber.add(1);
            _info.number = currentNumber;
        }else{
            require(_info.startDate > block.timestamp,'Governing!');
        }
        _info.startDate = _startDate;
        _info.endDate = _endDate;
        _info.uintValue = _uintValue;
        _info.addrValue = _addrValue;
        _info.totalVoter = memberReal;
        _info.approveVoter = 0;
        _info.opposeVoter = 0;
        _info.success = false;
        return _info;
    }

    //开启技术服务比例治理
    function startTPGovern(uint _techProportion,uint256 _startDate,uint256 _endDate) public isGovernance{
        require(_techProportion >= techDownLimit,'_techProportion is illegal!');
        GovernanceInfo memory info = _setGovern(governanceInfos[0], _techProportion, address(0), _startDate, _endDate);
        governanceInfos[0] = info;
    }

    //开启节点投资抵押最低下限治理
    function startPDLGovern(uint _fundsDownLimit,uint256 _startDate,uint256 _endDate) public isGovernance{
        GovernanceInfo memory info = _setGovern(governanceInfos[1], _fundsDownLimit, address(0), _startDate, _endDate);
        governanceInfos[1] = info;
    }

    //开启投资人数上限治理
    function startIULGovern(uint _investorUpLimit,uint256 _startDate,uint256 _endDate) public isGovernance{
        GovernanceInfo memory info = _setGovern(governanceInfos[2], _investorUpLimit, address(0), _startDate, _endDate);
        governanceInfos[2] = info;
    }

    //开启有效收集人地址治理
    function startFULGovern(address _collatorAddr,uint256 _startDate,uint256 _endDate) public isGovernance{
        GovernanceInfo memory info = _setGovern(governanceInfos[3], 0, _collatorAddr, _startDate, _endDate);
        governanceInfos[3] = info;
    }

    //开启每人次投资抵押下限治理
    function startPIDLGovern(uint _perInvestDownLimit,uint256 _startDate,uint256 _endDate) public isGovernance{
        GovernanceInfo memory info = _setGovern(governanceInfos[4], _perInvestDownLimit, address(0), _startDate, _endDate);
        governanceInfos[4] = info;
    }

    //开启投票参与人数比例治理
    function startVPGovern(uint _voterProportion,uint256 _startDate,uint256 _endDate) public isGovernance{
        require(_voterProportion >= voterDownLimit,'_voterProportion is illegal!');
        GovernanceInfo memory info = _setGovern(governanceInfos[5], _voterProportion, address(0), _startDate, _endDate);
        governanceInfos[5] = info;
    }

    //开启最低分配奖励额度治理
    function startRDGovern(uint _rewardDownLimit,uint256 _startDate,uint256 _endDate) public isGovernance{
        GovernanceInfo memory info = _setGovern(governanceInfos[6], _rewardDownLimit, address(0), _startDate, _endDate);
        governanceInfos[6] = info;
    }

    //开启治理人治理
    function startGAGovern(address _governanceAdmin,uint256 _startDate,uint256 _endDate) public isGovernance{
        GovernanceInfo memory info = _setGovern(governanceInfos[7], 0, _governanceAdmin, _startDate, _endDate);
        governanceInfos[7] = info;
    }

    //开启节点解散治理
    function startDBGovern(uint256 _startDate,uint256 _endDate) public isGovernance{
        require(redeemConfig.bondLessAddr == address(0) && redeemConfig.bondLess == 0 && redeemConfig.bondLessTime == 0,'Scheduling!');
        GovernanceInfo memory info = _setGovern(governanceInfos[8], 0, address(0), _startDate, _endDate);
        governanceInfos[8] = info;
    }

    //治理投票
    function _setVote(GovernanceInfo memory _info,uint _number,uint _state) private returns (GovernanceInfo memory){
        require(_number > 0 && _info.number == _number,'_number is illegal!');
        require(_state > 0 && _state < 3,'_state is illegal!');
        require(_info.startDate <= block.timestamp && _info.endDate >= block.timestamp,'Governace not started!');
        require(governanceVotes[_number][msg.sender] == 0,'Voted!');
        require(_info.totalVoter > 0 ,'totalVoter is illegal!');
        governanceVotes[_number][msg.sender] = _state;
        if(_state == 1){
            _info.approveVoter = _info.approveVoter.add(1);
        }else if(_state == 2){
            _info.opposeVoter = _info.opposeVoter.add(1);
        }
        if(_info.approveVoter.mul(100).div(_info.totalVoter) >= nodeConfig.voterProportion){
            _info.endDate = block.timestamp;
            _info.success = true;
        }
        return _info;
    }

    //技术服务比例治理投票
    function voteTPByNumber(uint _number,uint _state) public onlyRole(MEMBER){
        GovernanceInfo memory info = governanceInfos[0];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            nodeConfig.techProportion = info.uintValue;
        }
        governanceInfos[0] = info;
    }

    //节点投资抵押最低下限治理投票
    function votePDLByNumber(uint _number,uint _state) public onlyRole(MEMBER){
        GovernanceInfo memory info = governanceInfos[1];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            nodeConfig.fundsDownLimit = info.uintValue;
        }
        governanceInfos[1] = info;
    }

    //投资人数上限治理投票
    function voteIULByNumber(uint _number,uint _state) public onlyRole(MEMBER){
        GovernanceInfo memory info = governanceInfos[2];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            nodeConfig.investorUpLimit = info.uintValue;
        }
        governanceInfos[2] = info;
    }

    //有效收集人地址治理投票
    function voteCAByNumber(uint _number,uint _state) public onlyRole(MEMBER){
        GovernanceInfo memory info = governanceInfos[3];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            nodeConfig.collatorAddr = info.addrValue;
        }
        governanceInfos[3] = info;
    }

    //每人次投资抵押下限治理投票
    function votePIDLByNumber(uint _number,uint _state) public onlyRole(MEMBER){
        GovernanceInfo memory info = governanceInfos[4];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            nodeConfig.perInvestDownLimit = info.uintValue;
        }
        governanceInfos[4] = info;
    }

    //投票参与人数比例治理投票
    function voteVPByNumber(uint _number,uint _state) public onlyRole(MEMBER){
        GovernanceInfo memory info = governanceInfos[5];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            nodeConfig.voterProportion = info.uintValue;
        }
        governanceInfos[5] = info;
    }

    //最低分配奖励额度治理投票
    function voteRDByNumber(uint _number,uint _state) public onlyRole(MEMBER){
        GovernanceInfo memory info = governanceInfos[6];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            nodeConfig.rewardDownLimit = info.uintValue;
        }
        governanceInfos[6] = info;
    }

    //治理人治理投票
    function voteGAByNumber(uint _number,uint _state) public onlyRole(MEMBER){
        GovernanceInfo memory info = governanceInfos[7];
        info = _setVote(info, _number, _state);
        if(info.success){
            //治理成功
            nodeConfig.governanceAdmin = info.addrValue;
        }
        governanceInfos[7] = info;
    }

    //节点解散治理投票
    function voteDBByNumber(uint _number,uint _state) public onlyRole(MEMBER){
        GovernanceInfo memory info = governanceInfos[8];
        info = _setVote(info, _number, _state);
        if(info.success){
            //从提名节点计划赎回抵押
            governanceFlag = false;
            leaveTime = block.timestamp;
            staking.schedule_leave_delegators();         
        }
        governanceInfos[8] = info;
    }

    //分配当前奖励
    function _assign(uint256 newReward) private{
        require(totalStake > 0 ,'TotalStake is illegal!');
        uint256 stakeReward = newReward.sub(newReward.mul(nodeConfig.techProportion).div(100));
        for(uint i = 1; i < memberTotal; i++){
            address ra = memberAddrs[i];
            if(memberStakes[ra] > 0){
                uint256 reward = stakeReward.mul(memberStakes[ra]).div(totalStake);
                memberRedeems[ra] = memberRedeems[ra].add(reward);
                memberRewards[ra] = memberRewards[ra].add(reward);
                newReward = newReward.sub(reward);
            }
        }
        address ta = memberAddrs[0];
        memberRedeems[ta] = memberRedeems[ta].add(newReward);
        memberRewards[ta] = memberRewards[ta].add(newReward);
    }

    //节点解散,定时器触发使用sudo
    function executeLeaveStake() public isSchedule{
        require(leaveTime > 0 && (leaveTime + nodeConfig.scheduleTime) < block.timestamp, 'LeaveTime is not up!');
        require(governanceInfos[8].success,'Failed!');
        //从提名节点赎回抵押
        staking.execute_leave_delegators(address(this),staking.delegator_delegation_count(address(this)));
        leaveTime = 0;
        redeemConfig.bondLess = 0;
        redeemConfig.bondLessAddr = address(0);        
        redeemConfig.bondLessTime = 0;
        //存在未分配奖励        
        if((address(this).balance) - pendingReward > totalStake){
            uint256 newReward = (address(this).balance).sub(pendingReward).sub(totalStake);
            totalReward = totalReward.add(newReward);
            _assign(newReward);
        }
        pendingReward = address(this).balance;
        //抵押转入赎回
        for(uint i = 1; i < memberTotal; i++){
            address ra = memberAddrs[i];
            if(memberStakes[ra] > 0){
                memberRedeems[ra] = memberRedeems[ra].add(memberStakes[ra]);
                memberStakes[ra] = 0;
            }
        }
        nodeConfig.governanceAdmin = ownerAddress;
        memberTotal = 1;
        totalReward = 0;
        memberReal = 0;
        nodeStartDate = 0;
        totalStake = 0; 
    }

    //节点抵押
    function addStake() external payable {
        require(msg.sender != memberAddrs[0],'StakeAddr is illegal!');
        require(block.timestamp < nodeStartDate,'StakTime is expired!');
        require(msg.value >= nodeConfig.perInvestDownLimit,'Less than perInvestDownLimit!');
        if(!hasRole(MEMBER, msg.sender)){
            require(memberReal <= nodeConfig.investorUpLimit,'More than investorUpLimit!');
            memberAddrs[memberTotal] = msg.sender;
            memberTotal = memberTotal.add(1);
            memberReal = memberReal.add(1);
            _setupRole(MEMBER, msg.sender);
        }
        memberStakes[msg.sender] = memberStakes[msg.sender].add(msg.value);
        totalStake = totalStake.add(msg.value);        
    }

    //增加节点抵押
    function addMoreStake() external payable onlyRole(MEMBER){
        require(msg.sender != memberAddrs[0],'StakeAddr is tech!');
        require(governanceFlag,'Node not started!');
        memberStakes[msg.sender] = memberStakes[msg.sender].add(msg.value);
        totalStake = totalStake.add(msg.value);
        staking.delegator_bond_more(nodeConfig.collatorAddr,msg.value);
    }
    
    //计划赎回节点抵押，同一时间段只能赎回一次
    function scheduleRedeemStake(uint amount) public onlyRole(MEMBER){
        require(governanceFlag,'Node not started!');
        require(governanceInfos[8].number == 0 || (!governanceInfos[8].success && governanceInfos[8].endDate < block.timestamp), 'Governing!');
        require(amount > 0 && amount <= memberStakes[msg.sender],'Amount is illegal!');
        require(totalStake - amount >= nodeConfig.fundsDownLimit,'Less than fundsDownLimit!');
        require(redeemConfig.bondLessAddr == address(0),'Scheduling!');
        //从提名节点赎回抵押
        redeemConfig.bondLess = amount;
        redeemConfig.bondLessAddr = msg.sender;        
        redeemConfig.bondLessTime = block.timestamp;
        staking.schedule_delegator_bond_less(nodeConfig.collatorAddr, amount);
    }

    //赎回节点抵押,定时器触发使用sudo
    function executeRedeemStake() public isSchedule{
        require(redeemConfig.bondLessTime > 0 && (redeemConfig.bondLessTime + nodeConfig.scheduleTime) < block.timestamp, 'BondLessTime is not up!');
        staking.execute_delegation_request(address(this), nodeConfig.collatorAddr);
        pendingReward = pendingReward.add(redeemConfig.bondLess);
        memberStakes[redeemConfig.bondLessAddr] = memberStakes[redeemConfig.bondLessAddr].sub(redeemConfig.bondLess);
        if(memberStakes[redeemConfig.bondLessAddr] == 0){
            memberReal = memberReal.sub(1);
        }
        memberRedeems[redeemConfig.bondLessAddr] = memberRedeems[redeemConfig.bondLessAddr].add(redeemConfig.bondLess);
        totalStake = totalStake.sub(redeemConfig.bondLess);
        redeemConfig.bondLess = 0;
        redeemConfig.bondLessAddr = address(0);
        redeemConfig.bondLessTime = 0;
    }

    //节点开启（关闭抵押）,治理开启,定时器触发使用sudo
    function start() public isOwner{
        require(!governanceFlag,'Node started!');
        require(block.timestamp >= nodeStartDate && nodeStartDate > 0,'Node not started!');
        require(nodeConfig.collatorAddr != address(0),'Collator not seted!');
        require(address(this).balance >= totalStake && totalStake >= nodeConfig.fundsDownLimit ,'TotalStake is illegal!');
        //开始进行提名人抵押
        staking.delegate(nodeConfig.collatorAddr,totalStake, staking.candidate_delegation_count(nodeConfig.collatorAddr), staking.delegator_delegation_count(address(this)));
        governanceFlag = true;
    }

    //节点众贷失败解散,定时器触发使用sudo
    function failBackStake() public isOwner{
        require(!governanceFlag,'Node started!');
        require(leaveTime == 0,'Node disbanding!');
        require(memberTotal > 1,'memberTotal is illegal!');
        require(block.timestamp >= nodeStartDate && nodeStartDate > 0,'Node not started!');
        require(totalStake < nodeConfig.fundsDownLimit ,'TotalStake is illegal!');
        for(uint i = 1; i < memberTotal; i++){
            address ra = memberAddrs[i];
            if(memberStakes[ra] > 0){
                memberRedeems[ra] = memberRedeems[ra].add(memberStakes[ra]);
                memberStakes[ra] = 0;
            }
        }
        pendingReward = address(this).balance;
        memberTotal = 1;
        totalReward = 0;
        memberReal = 0;
        nodeStartDate = 0;
        totalStake = 0; 
    }

    //申领奖励(包括解散赎回)
    function claimRedeem(address payable account) public onlyRole(MEMBER){
        require(account != address(0),'Account is illegal!');
        require(memberRedeems[msg.sender] > 0,'MemberRedeems is illegal!');
        require(pendingReward <= address(this).balance,'PendingReward is illegal!');
        uint256 reddeem = memberRedeems[msg.sender];
        require(pendingReward - reddeem >= 0,'PendingReward not enough!');
        pendingReward = pendingReward.sub(reddeem);
        memberRedeems[msg.sender] = 0;
        if(memberStakes[msg.sender] == 0){
            _revokeRole(MEMBER, msg.sender);
        }
        Address.sendValue(account, reddeem);        
    }

    //奖励分配,定时器触发使用sudo
    function assignRewards() public isSchedule{
        require(governanceFlag,'Node not started!');
        // require(redeemConfig.bondLessAddr == address(0),'Scheduling!');
        require((address(this).balance) - pendingReward >= nodeConfig.rewardDownLimit,'Balance not enough!');
        uint256 newReward = (address(this).balance).sub(pendingReward);
        pendingReward = address(this).balance;
        totalReward = totalReward.add(newReward);
        _assign(newReward);
    }

    //抵押转让
    function fundsTransfer(address payable account) public onlyRole(MEMBER){
        require(account != memberAddrs[0] && msg.sender != account && account != address(0),'Account is illegal!');
        require(memberStakes[msg.sender] > 0,'No stake!');
        if(!hasRole(MEMBER, account)){
            memberAddrs[memberTotal] = account;
            memberTotal = memberTotal.add(1);
            memberReal = memberReal.add(1);
            _setupRole(MEMBER, account);
        }
        memberStakes[account] = memberStakes[account].add(memberStakes[msg.sender]);
        memberStakes[msg.sender] = 0;
        memberReal = memberReal.sub(1);
        if(memberRedeems[msg.sender] == 0){
            _revokeRole(MEMBER,msg.sender);
        }
    }

    //获取节点当前余额
    function getBalance() public view returns(uint256){
        return address(this).balance;
    }

    //查看奖励
    function getReward() public view returns(uint256){
        return memberRewards[msg.sender];
    }

    //查看赎回
    function getRedeem() public view returns(uint256){
        return memberRedeems[msg.sender];
    }

    //查看抵押
    function getStake() public view returns(uint256){
        return memberStakes[msg.sender];
    }

    //查看节点总抵押
    function getTotalStake() public view returns(uint256){
        return totalStake;
    }

    //查看抵押所占比例
    function getStakeProportion() public view returns(uint256){
        if(totalStake <= 0)  return 0;
        return memberStakes[msg.sender].mul(100).div(totalStake);
    }

    //查看节点总奖励
    function getTotalReward() public view returns(uint256){
        return totalReward;
    }

    //查看节点待领取奖励
    function getPendingReward() public view returns(uint256){
        return pendingReward;
    }    

    //查看年化奖励
    function getAnnualReward() public view returns(uint256){
        if(totalStake <= 0 || block.timestamp < nodeStartDate) return 0;
        uint256 day = ((block.timestamp).sub(nodeStartDate)).div(60 * 60 *24);
        if(day <= 0) return 0;
        return totalReward.mul(365 * 100).div(totalStake).div(day);
    }

    //查看节点成员人数
    function getMemberReal() public view returns(uint){
        return memberReal;
    }

    //查看节点历史成员总人数
    function getMemberTotal() public view returns(uint){
        return memberTotal;
    }

    //根据索引查看节点成员地址
    function getMemberByIndex(uint _index) public view returns(address){
        return memberAddrs[_index];
    }

    //查看节点开启日期
    function getNodeStartDate() public view returns(uint256){
        return nodeStartDate;
    }

    //查看计划解散时间
    function getLeaveTime() public view returns(uint256){
        return leaveTime;
    }

    //查看节点状态 0未开启 1开启 2解散中 3已解散
    function getNodeState() public view returns(uint){
        uint state = 0;
        if(governanceFlag){
            state = 1;
        }else if(leaveTime > 0){
            state = 2;
        }else if(nodeStartDate == 0){
            state = 3;
        }
        return state;
    }

    //查看节点配置信息
    function getNodeConfig() public view returns(NodeConfig memory){
        return nodeConfig;
    }

    //查看节点治理信息
    function getGovernanceInfo(uint _type) public view returns(GovernanceInfo memory){
        return governanceInfos[_type];
    }
    
    //查看赎回信息
    function getRedeemConfig()public view returns(RedeemConfig memory){
        return redeemConfig;
    }
}