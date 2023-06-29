// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.6.8;
// pragma experimental ABIEncoderV2;
contract NftDAO {
    //通证名称
    string constant private tokenName = "NFT BY DAO.TECH";
    //通证代号 
    string constant private tokenSymbol = "NftDAO";
    //总发行量，这里设置为0不限制发行量 
    uint256 constant private totalTokens = 0;
    //根据地址获取nft数量 balanceCount[_owner] = _count _owner为nft所有者地址 _count为nft数量
    mapping(address => uint) private balanceCount;
    //根据nft唯一标识获取nft所有者地址 tokenOwners[_tokenId] = _address _tokenId为nft唯一标识 _address为nft所有者地址 
    mapping(uint256 => address) private tokenOwners;
    //根据nft唯一标识判断nft是否存在 tokenOwners[_tokenId] = _bool _tokenId为nft唯一标识 _bool值为真已铸造 
    mapping(uint256 => bool) private tokenExists;
    //将所属nft授权给指定地址
    mapping(address => mapping (uint256 => address)) private allowed;
    //根据地址获取所有nft唯一标识 
    mapping(address => mapping (uint256 => uint256)) private ownerTokens;
    //铸造NFT数量 ID从1000开始 
    uint256  private mintCount  = 1000;
    //铸造手续费 对应NFTMetaData的class
    mapping(uint256 => uint256) private mintFee;
    //交易手续费费率
    uint private tradeRate;
    //二手交易原创分成费率（2著作权 10其他）
    uint private divideInto;
    //NftDAO对象信息
    struct NFTMetaData{
        address authorAddress; //原创作者（原始拥有者）
        string name;//铸造nft名称
        string webUrl;//铸造nft扩展说明的web地址
        string ipfsUrl;//铸造nft上传资料的ipfs地址
        uint class; //铸造类型：0专利 1商标 2著作权 10其他
        uint256 startDate;//nft生效时间 
        uint256 dendDate;//nft失效时间
    }
    mapping(uint256 => NFTMetaData) private NFTMetaDatas;
    //NftDAO许可信息（专利、商标、著作权）
    struct NFTAllowInfo{
        address allowAddress;//许可地址
        string webUrl;//许可nft扩展说明的web地址
        string ipfsUrl;//许可nft上传资料的ipfs地址
        uint allowType; //许可类型：1独占(使用)许可 2排他(使用)许可 3普通(使用)许可 4分许可 5交叉许可（专利包含1-5，商标包含1-3，著作权1-3）
        uint256 price;//许可价格
        uint256 startDate;//许可生效时间 
        uint256 dendDate;//许可失效时间
    }
    //根据nft唯一标识获取所有nft许可信息
    mapping(uint256 => uint256) private NFTAllowNums;
    mapping(uint256 => mapping (uint256 => NFTAllowInfo)) private NFTAllowInfos;
    //根据地址获取所有nft许可信息
    mapping(address => mapping (uint256 => NFTAllowInfo)) private addressAllowInfos;
    //NftDAO设置价格 ownerPrices[_tokenId][_allowType] = _price _tokenId为nft唯一标识  _allowType为0转让，其他则同NFTAllowInfo的allowType
    mapping(uint256 => mapping (uint => uint256)) private ownerPrices;
    //合格合约管理者
    address private ownerAddr;
    //多部门签名地址池 signAddressPools[_no] = _address _no为部门编号
    mapping(uint => address) private signAddressPools;
    //多部门签名信息 signAddressInfos[_tokenId][_no] = _address _tokenId为nft唯一标识  _no为部门编号
    mapping(uint256 => mapping (uint => address)) private signAddressInfos;
    //限制使用tx.origin时外部合约钓鱼欺骗 
    mapping(address => bool) private contractAddrExists;
    constructor() public{
        ownerAddr = msg.sender;
    }
   
    modifier isOwnerAddr() { 
        require(msg.sender == ownerAddr);
        _;
    }
    //铸造NftDAO
    function _mint(address _authorAddress,string memory _name,string memory _webUrl,
                    string memory _ipfsUrl,uint _class,uint256 _startDate,
                    uint256 _dendDate,uint256 _money) private returns (uint256){
        require(_authorAddress != address(0),'_authorAddress is illegal');
        require(bytes(_name).length > 0,'_name is illegal');
        require(_class >= 0,'_class is illegal');
        uint256 tokenId = mintCount;
        require(!tokenExists[tokenId],'tokenId is existed');
        if(_money > 0){
            (bool success,) = ownerAddr.call{value:_money}(new bytes(0));
            // bool success = ownerAddr.send(_money);
            require(success, '_mint: ETH_TRANSFER_FAILED');
        }
        mintCount += 1;
        balanceCount[_authorAddress] += 1;
        tokenExists[tokenId] = true;
        tokenOwners[tokenId] = _authorAddress;
        ownerTokens[_authorAddress][balanceCount[_authorAddress]-1] = tokenId;
        NFTMetaData memory metaData;
        metaData.authorAddress = _authorAddress;
        metaData.name = _name;
        metaData.webUrl = _webUrl;
        metaData.ipfsUrl = _ipfsUrl;
        metaData.class = _class;
        metaData.startDate = _startDate;
        metaData.dendDate = _dendDate;
        NFTMetaDatas[tokenId] = metaData;
        return tokenId;
    }
    //从ownerTokens中移除指定nft
    function _removeFromTokenList(address owner, uint256 _tokenId) private {
        uint count = balanceCount[owner];
        for(uint256 i = 0; i < count; i++){
            if(ownerTokens[owner][i] == _tokenId){
                if(i == count - 1)
                    ownerTokens[owner][i] = 0;
                else
                    ownerTokens[owner][i] = ownerTokens[owner][count-1];
                balanceCount[owner] -= 1;
                i = count;
            }
        }
    }
    //nft转移
    function _transfer(address _from, address _to, uint256 _tokenId) private{
        _removeFromTokenList(_from, _tokenId);
        tokenOwners[_tokenId] = _to;
        ownerTokens[_to][balanceCount[_to]] = _tokenId;
        balanceCount[_to] += 1;
        allowed[_from][_tokenId] = address(0);
    }
    //购买nft
    function _buy(address _from,address _to, uint256 _tokenId,uint256 _money) private{
        require(_from != address(0) && _from == ownerOf(_tokenId),'_from is illegal');
        require(_from != _to,'_from and _to is same');
        address _allowed = allowed[_from][_tokenId];
        require(_allowed != address(0) && _allowed == ownerAddr,'_allowed is illegal');//授权给ownerAddr地址的nft才能进行销售
        if(_money > 0){
            if(tradeRate > 0){
                (bool success,) = ownerAddr.call{value:_money * tradeRate / 100}(new bytes(0));
                // bool success = ownerAddr.send(_money * tradeRate / 100);
                require(success, '_buy-tradeRate: ETH_TRANSFER_FAILED');
            }
            NFTMetaData memory datas = NFTMetaDatas[_tokenId];
            address authorAddress = datas.authorAddress;
            if(authorAddress != tokenOwners[_tokenId] && datas.class >= 2 && divideInto > 0){
                (bool success1,) = authorAddress.call{value:_money * divideInto / 100}(new bytes(0));
                // bool success1 = authorAddress.send(_money * divideInto / 100);
                require(success1, '_buy-divideInto: ETH_TRANSFER_FAILED');
                (bool success2,) = _from.call{value:_money - _money * tradeRate / 100 - msg.value * divideInto / 100}(new bytes(0));
                // bool success2 = _from.send(_money - _money * tradeRate / 100 - _money * divideInto / 100);
                require(success2, '_buy: ETH_TRANSFER_FAILED');
            }else{
                (bool success3,) = _from.call{value:_money - _money * tradeRate / 100}(new bytes(0));
                // bool success3 = _from.send(_money - _money * tradeRate / 100);
                require(success3, '_buy: ETH_TRANSFER_FAILED');
            }
        }
    }
    //NftDAO许可
    function _allow(address _currentOwner,string memory _webUrl,string memory _ipfsUrl,
                    uint256 _startDate,uint256 _dendDate,uint _allowType,
                    uint256 _tokenId,uint256 _money) private{
        require(tokenExists[_tokenId], '_tokenId is not exist');
        require(_currentOwner != address(0), '_currentOwner is illegal');
        require(_allowType > 0 && _allowType < 6, '_allowType is illegal');
        require(_startDate > 0 && _dendDate > 0, '_startDate or _dendDate is illegal');
        if(_money > 0){
            NFTMetaData memory datas = NFTMetaDatas[_tokenId];
            address authorAddress = datas.authorAddress;
            (bool success,) = authorAddress.call{value:_money}(new bytes(0));
            // bool success = authorAddress.send(_money);
            require(success, 'allow: ETH_TRANSFER_FAILED');
        }
        NFTAllowInfo memory allowInfo;
        allowInfo.allowAddress = _currentOwner;
        allowInfo.webUrl = _webUrl;
        allowInfo.ipfsUrl = _ipfsUrl;
        allowInfo.allowType = _allowType;
        allowInfo.price = ownerPrices[_tokenId][_allowType];
        allowInfo.startDate = _startDate;
        allowInfo.dendDate = _dendDate;
        uint256 len = NFTAllowNums[_tokenId];
        NFTAllowNums[_tokenId] += 1;
        NFTAllowInfos[_tokenId][len] = allowInfo;
        addressAllowInfos[_currentOwner][len] = allowInfo;
    }
    //设置nft销售和许可价格 _price默认单位为wei
    function _setPrice(uint256 _tokenId,uint256[] memory _price) private{
        for(uint i = 0;i < _price.length;i++){
            if(_price[i] > 0)
                ownerPrices[_tokenId][i] = _price[i];
            else
                ownerPrices[_tokenId][i] = 0;
        }
    }
    //设置交易和分成费率 设置nft铸造手续费 _fee默认单位为wei
    function setFeeRate(uint _tradeRate,uint _divideInto,uint256[] memory _fee) isOwnerAddr public{
        require(_tradeRate >= 0 && _tradeRate < 100,'_tradeRate is illegal');
        require(_divideInto >= 0  && _divideInto < 100,'_divideInto is illegal');
        require(_fee.length > 0 && _fee.length <= 10,'_fee is illegal');
        tradeRate = _tradeRate;
        divideInto = _divideInto;
        for(uint i = 0;i < _fee.length;i++){
            if(_fee[i] > 0)
                mintFee[i] = _fee[i];
            else
                mintFee[i] = 0;
        }
    }
    //设置多部门签名地址 数组下标为部门编号
    function setSignAddress(address[] memory _address) isOwnerAddr public{
        require(_address.length > 0,'_addresss is illegal');
        for(uint i = 0;i < _address.length;i++){
            if(_address[i] != address(0))
                signAddressPools[i] = _address[i];
            else
                signAddressPools[i] = address(0);
        }
    }
    //设置外部合约可调用地址
    function setContractAddress(address[] memory _address) isOwnerAddr public{
        require(_address.length > 0,'_addresss is illegal');
        for(uint i = 0;i < _address.length;i++){
            if(_address[i] != address(0))
                contractAddrExists[_address[i]] = true;
            else
                contractAddrExists[_address[i]] = false;
        }
    }
    //nft部门签名 
    function nftSign(uint256 _tokenId, uint _no) public{
        require(tokenExists[_tokenId],'_tokenId is not exist');
        address signAddr = signAddressPools[_no];
        require(signAddr != address(0),'_no is illegal');
        require(signAddr == msg.sender || (contractAddrExists[msg.sender] && tx.origin == signAddr),'msg.sender is illegal');
        require(signAddressInfos[_tokenId][_no] == address(0),'_tokenId or _no is illegal');
        signAddressInfos[_tokenId][_no] = tx.origin;
    }
    //nft部门撤销签名 
    function cancelNftSign(uint256 _tokenId, uint _no) public{
        require(tokenExists[_tokenId],'_tokenId is not exist');
        address signAddr = signAddressPools[_no];
        require(signAddr != address(0),'_no is illegal');
        require(signAddr == msg.sender || (contractAddrExists[msg.sender] && tx.origin == signAddr),'msg.sender is illegal');
        require(signAddressInfos[_tokenId][_no] != address(0),'_tokenId or _no is illegal');
        signAddressInfos[_tokenId][_no] = address(0);
    }
    //设置nft销售和许可价格 _price默认单位为wei
    function setPrice(uint256 _tokenId,uint256[] memory _price) public{
        require(tokenExists[_tokenId],'_tokenId is not exist');
        require(msg.sender == ownerOf(_tokenId) || (contractAddrExists[msg.sender] && tx.origin == ownerOf(_tokenId)),' msg.sender is illegal');
        require(_price.length > 0 && _price.length < 7,'_price is illegal');
        _setPrice(_tokenId,_price);
    }
    //授权铸造nft
    function approveMint(address _approved,uint _class,string memory _name,
                        string memory _webUrl,string memory _ipfsUrl,uint256 _startDate,
                        uint256 _dendDate,uint256[] memory _price)  public payable returns (uint256){
        require(ownerAddr == msg.sender || (contractAddrExists[msg.sender] && tx.origin == ownerAddr),'msg.sender is illegal');
        require(_class >= 0 && _class <= 10,'_class is illegal');
        require(_price.length > 0 && _price.length < 7,'_price is illegal');
        //require(msg.value >= mintFee[_class],'msg.value is illegal');
        uint256 tokenId =  _mint(_approved,_name,_webUrl,_ipfsUrl,_class,_startDate,_dendDate,msg.value);
        _setPrice(tokenId,_price);
        allowed[_approved][tokenId] = ownerAddr;
        return tokenId;
    }
    //本人铸造nft
    function mint(uint _class,string memory _name,string memory _webUrl,
                    string memory _ipfsUrl,uint256 _startDate,uint256 _dendDate,
                    uint256[] memory _price) public payable returns (uint256){
        require(msg.sender == tx.origin || contractAddrExists[msg.sender],'msg.sender is illegal');
        require(_class >= 0 && _class <= 10,'_class is illegal');
        require(_price.length > 0 && _price.length < 7,'_price  is illegal');
        require(msg.value >= mintFee[_class],'msg.value is illegal');
        uint256 tokenId =  _mint(tx.origin,_name,_webUrl,_ipfsUrl,_class,_startDate,_dendDate,msg.value);
        _setPrice(tokenId,_price);
        return tokenId;
    }
    //授权NftDAO许可
    function approveAllow(address _approved,string memory _webUrl,string memory _ipfsUrl,
                            uint256 _startDate,uint256 _dendDate,uint _allowType,
                            uint256 _tokenId)  public payable{
        require(ownerAddr == msg.sender || (contractAddrExists[msg.sender] && tx.origin == ownerAddr),'msg.sender is illegal');
        //require(msg.value >= ownerPrices[_tokenId][_allowType], 'msg.value is illegal');
        _allow(_approved,_webUrl,_ipfsUrl,_startDate,_dendDate,_allowType,_tokenId,msg.value);
    }
    //本人NftDAO许可
    function allow(string memory _webUrl,string memory _ipfsUrl,uint256 _startDate,
                    uint256 _dendDate,uint _allowType,uint256 _tokenId) public payable{
        require(msg.sender == tx.origin || contractAddrExists[msg.sender],'msg.sender is illegal');
        require(msg.value >= ownerPrices[_tokenId][_allowType], 'msg.value is illegal');
        _allow(tx.origin,_webUrl,_ipfsUrl,_startDate,_dendDate,_allowType,_tokenId,msg.value);
    }
    //销毁NftDAO(发送到address(0)销毁)
    function burn(uint256 _tokenId) public{
        require(tokenExists[_tokenId],'_tokenId is not exist');
        require(msg.sender == ownerOf(_tokenId) || (contractAddrExists[msg.sender] && tx.origin == ownerOf(_tokenId)),'msg.sender is illegal');
        _removeFromTokenList(tx.origin, _tokenId);
        tokenOwners[_tokenId] = address(0);
        allowed[tx.origin][_tokenId] = address(0);
    }
    //获取通证名称
    function name() public pure returns (string memory){
        return tokenName;
    }
    //获取通证代号
    function symbol() public pure returns (string memory) {
        return tokenSymbol;
    }
    //根据地址获取nft数量
    function balanceOf(address _owner) public view returns (uint){
        return balanceCount[_owner];
    }
    //根据nft唯一标识获取nft所有者地址
    function ownerOf(uint256 _tokenId) public view returns (address){
        return tokenOwners[_tokenId];
    }
    //将所属nft授权给指定地址,取消授权_to=address(0)
    function approve(address _to, uint256 _tokenId) public{
        require(msg.sender == ownerOf(_tokenId) || (contractAddrExists[msg.sender] && tx.origin == ownerOf(_tokenId)),'msg.sender or _tokenId is illegal');
        require(msg.sender != _to,'approve: msg.sender or _to  is illegal');
        allowed[tx.origin][_tokenId] = _to;
    }
    //提取已授权的nft 
    function takeOwnership(uint256 _tokenId) public{
        require(tokenExists[_tokenId],'tokenId is not exist');
        address oldOwner = ownerOf(_tokenId);
        address allowedAddr = allowed[oldOwner][_tokenId];
        require(allowedAddr == msg.sender || (contractAddrExists[msg.sender] && tx.origin == allowedAddr),'msg.sender is illegal');
        require(msg.sender != oldOwner && msg.sender != ownerAddr,'msg.sender is illegal');//授权给ownerAddr地址的nft不能提取
        _transfer(oldOwner,tx.origin,_tokenId);
    }
    //将nft转移到指定地址
    function transfer(address _to, uint256 _tokenId) public{
        require(tokenExists[_tokenId],'tokenId is not exist');
        require(msg.sender == ownerOf(_tokenId) || (contractAddrExists[msg.sender] && tx.origin == ownerOf(_tokenId)),'msg.sender is illegal');
        require(_to != address(0),'_to is illegal');
        require(msg.sender != _to,'msg.sender and _to is same');
        _transfer(tx.origin,_to,_tokenId);
    }
    //授权购买nft
    function approveBuy(address _approved,address _from, uint256 _tokenId) public payable{
        require(tokenExists[_tokenId],'tokenId is not exist');
        require(ownerAddr == msg.sender || (contractAddrExists[msg.sender] && tx.origin == ownerAddr),'msg.sender is illegal');
        //require(msg.value >= ownerPrices[_tokenId][0],'msg.value is illegal');
        _buy(_from,_approved,_tokenId,msg.value);
        _transfer(_from,_approved,_tokenId);
    }
    //本人购买nft
    function buy(address _from, uint256 _tokenId) public payable{
        require(tokenExists[_tokenId],'tokenId is not exist');
        require(msg.sender == tx.origin || contractAddrExists[msg.sender],'msg.sender is illegal');
        require(msg.value >= ownerPrices[_tokenId][0],'msg.value is illegal');
        _buy(_from,tx.origin,_tokenId,msg.value);
        _transfer(_from,tx.origin,_tokenId);
    }
    //根据指定地址和索引获取nft
    function tokenOfOwnerByIndex(address _owner, uint256 _index) public view returns (uint){
        return ownerTokens[_owner][_index];
    }
    //根据nft唯一标识获取meta
    function tokenMetadata(uint256 _tokenId) public view returns (address, string memory, string memory, 
    string memory, uint, uint256, uint256){
        NFTMetaData memory datas = NFTMetaDatas[_tokenId];
        return (datas.authorAddress, 
        datas.name, 
        datas.webUrl, 
        datas.ipfsUrl, 
        datas.class, 
        datas.startDate, 
        datas.dendDate);
    }
    //根据nft唯一标识获取nft许可信息
    function tokenAllowInfo(uint256 _tokenId, uint256 _index) public view returns (address, string memory, string memory, 
    uint, uint256, uint256, uint256) {
        NFTAllowInfo memory info = NFTAllowInfos[_tokenId][_index];
        return (info.allowAddress, 
        info.webUrl, 
        info.ipfsUrl, 
        info.allowType, 
        info.price, 
        info.startDate, 
        info.dendDate);
    }
    //根据地址获取nft许可信息
    function addressAllowInfo(address _owner, uint256 _index) public view returns (address, string memory, string memory, 
    uint, uint256, uint256, uint256){
        NFTAllowInfo memory info = addressAllowInfos[_owner][_index];
        return (info.allowAddress, 
        info.webUrl, 
        info.ipfsUrl, 
        info.allowType, 
        info.price, 
        info.startDate, 
        info.dendDate);
    }
    //获取多部门签名地址 数组下标为部门编号
    function getSignAddress(uint _no) public view returns (address){
        return signAddressPools[_no];
    }
    //获取外部合约可调用地址
    function isContractAddress(address _address) public view returns (bool){
        return contractAddrExists[_address];
    }
    //获取nft部门签名 
    function getNftSign(uint256 _tokenId, uint _no) public view returns (address){
        return signAddressInfos[_tokenId][_no];
    }
    //获取nft销售和许可价格
    function getPrice(uint256 _tokenId,uint _index) public view returns (uint256){
        return ownerPrices[_tokenId][_index];
    }
    //获取交易和分成费率
    function getRate() public view returns (uint, uint){
        return (tradeRate,divideInto);
    }
    //获取nft铸造手续费
    function getFee(uint _index) public view returns (uint256){
        return mintFee[_index];
    }
    
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}