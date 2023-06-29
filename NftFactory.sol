// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.4.26;
// pragma experimental ABIEncoderV2;

interface INftDAO {
    //nft部门签名 
    function nftSign(uint256 _tokenId, uint _no) external;
    //nft部门撤销签名 
    function cancelNftSign(uint256 _tokenId, uint _no) external;
    //设置nft销售和许可价格 _price默认单位为wei
    function setPrice(uint256 _tokenId,uint256[] _price) external;
    //授权铸造nft
    function approveMint(address _approved,uint _class,string  _name,
                        string  _webUrl,string  _ipfsUrl,uint256 _startDate,
                        uint256 _dendDate,uint256[]  _price)  external payable returns (uint256);
    //本人铸造nft
    function mint(uint _class,string  _name,string  _webUrl,
                string  _ipfsUrl,uint256 _startDate,uint256 _dendDate,
                uint256[]  _price) external payable returns (uint256);
    //授权NftDAO许可
    function approveAllow(address _approved,string  _webUrl,string  _ipfsUrl,
                        uint256 _startDate,uint256 _dendDate,uint _allowType,
                        uint256 _tokenId)  external payable;
    //本人NftDAO许可
    function allow(string  _webUrl,string  _ipfsUrl,uint256 _startDate,
                    uint256 _dendDate,uint _allowType,uint256 _tokenId) external payable;
    //销毁NftDAO(发送到address(0)销毁)
    function burn(uint256 _tokenId) external;
    //根据地址获取nft数量
    function balanceOf(address _owner) external view returns (uint);
    //根据nft唯一标识获取nft所有者地址
    function ownerOf(uint256 _tokenId) external view returns (address);
    //将所属nft授权给指定地址,取消授权_to=address(0)
    function approve(address _to, uint256 _tokenId) external;
    //提取已授权的nft 
    function takeOwnership(uint256 _tokenId) external;
    //将nft转移到指定地址
    function transfer(address _to, uint256 _tokenId) external;
    //授权购买nft
    function approveBuy(address _approved,address _from, uint256 _tokenId) external payable;
    //本人购买nft
    function buy(address _from, uint256 _tokenId) external payable;
    //根据指定地址和索引获取nft
    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint);
    //根据nft唯一标识获取meta
    function tokenMetadata(uint256 _tokenId) external view returns (address, string memory, string memory, string memory, uint, uint256, uint256);
    //根据nft唯一标识获取nft许可信息
    function tokenAllowInfo(uint256 _tokenId, uint256 _index) external view returns (address, string memory, string memory, uint, uint256, uint256, uint256);
    //根据地址获取nft许可信息
    function addressAllowInfo(address _owner, uint256 _index) external view returns (address, string memory, string memory, uint, uint256, uint256, uint256);
    //获取通证名称
    function name() external pure returns (string memory);
    //获取通证代号
    function symbol() external pure returns (string memory);
    //获取多部门签名地址 数组下标为部门编号
    function getSignAddress(uint _no) external view returns (address);
    //获取外部合约可调用地址
    function isContractAddress(address _address) external view returns (bool);
    //获取nft部门签名 
    function getNftSign(uint256 _tokenId, uint _no) external view returns (address);
    //获取nft销售和许可价格
    function getPrice(uint256 _tokenId,uint _index) external view returns (uint256);
    //获取交易和分成费率
    function getRate() external view returns (uint, uint);
    //获取nft铸造手续费
    function getFee(uint _index) external view returns (uint256);
}

contract NftFactory {
    INftDAO public nftDAO;
    
    constructor(address nftAddress) public{
        nftDAO = INftDAO(nftAddress);
    }
    //nft部门签名 
    function nftSign(uint256 _tokenId, uint _no) public{
        nftDAO.nftSign(_tokenId,_no);
        emit Event(true);
    }
    //nft部门撤销签名 
    function cancelNftSign(uint256 _tokenId, uint _no) public{
        nftDAO.cancelNftSign(_tokenId,_no);
        emit Event(true);
    }
    //设置nft销售和许可价格 _price默认单位为wei
    function setPrice(uint256 _tokenId,uint256[] memory _price) public{
        nftDAO.setPrice(_tokenId,_price);
        emit Event(true);
    }
    //授权铸造nft
    function approveMint(address _approved,uint _class,string memory _name,
                        string memory _webUrl,string memory _ipfsUrl,uint256 _startDate,
                        uint256 _dendDate,uint256[] memory _price)  public payable returns (uint256){
        uint256 tokenId = nftDAO.approveMint.value(msg.value)(_approved,_class,_name,_webUrl,_ipfsUrl,_startDate,_dendDate,_price);
        emit Mint(_approved,tokenId);
        return tokenId;
    }
    //本人铸造nft
    function mint(uint _class,string memory _name,string memory _webUrl,
                string memory _ipfsUrl,uint256 _startDate,uint256 _dendDate,
                uint256[] memory _price) public payable returns (uint256){
        uint256 tokenId = nftDAO.mint.value(msg.value)(_class,_name,_webUrl,_ipfsUrl,_startDate,_dendDate,_price);
        emit Mint(msg.sender,tokenId);
        return tokenId;
    }
    //授权NftDAO许可
    function approveAllow(address _approved,string memory _webUrl,string memory _ipfsUrl,
                        uint256 _startDate,uint256 _dendDate,uint _allowType,
                        uint256 _tokenId)  public payable{
        nftDAO.approveAllow.value(msg.value)(_approved,_webUrl,_ipfsUrl,_startDate,_dendDate,_allowType,_tokenId);
        emit Event(true);
    }
    //本人NftDAO许可
    function allow(string memory _webUrl,string memory _ipfsUrl,uint256 _startDate,
                uint256 _dendDate,uint _allowType,uint256 _tokenId) public payable{
        nftDAO.allow.value(msg.value)(_webUrl,_ipfsUrl,_startDate,_dendDate,_allowType,_tokenId);
        emit Event(true);
    }
    
    //销毁NftDAO(发送到address(0)销毁)
    function burn(uint256 _tokenId) public{
        nftDAO.burn(_tokenId);
        emit Transfer(msg.sender, address(0), _tokenId);
    }
    //根据地址获取nft数量
    function balanceOf(address _owner) public view returns (uint){
        return nftDAO.balanceOf(_owner);
    }
    //根据nft唯一标识获取nft所有者地址
    function ownerOf(uint256 _tokenId) public view returns (address){
        return nftDAO.ownerOf(_tokenId);
    }
    //将所属nft授权给指定地址,取消授权_to=address(0)
    function approve(address _to, uint256 _tokenId) public{
        nftDAO.approve(_to,_tokenId);
        emit Approval(msg.sender, _to, _tokenId);
    }
    //提取已授权的nft 
    function takeOwnership(uint256 _tokenId) public{
        address oldOwner = nftDAO.ownerOf(_tokenId);
        nftDAO.takeOwnership(_tokenId);
        emit Transfer(oldOwner, msg.sender, _tokenId);
    }
    //将nft转移到指定地址
    function transfer(address _to, uint256 _tokenId) public{
        nftDAO.transfer(_to,_tokenId);
        emit Transfer(msg.sender, _to, _tokenId);
    }
    //授权购买nft
    function approveBuy(address _approved,address _from, uint256 _tokenId) public payable{
        nftDAO.approveBuy.value(msg.value)(_approved,_from,_tokenId);
        emit Transfer(_from, _approved, _tokenId);
    }
    //本人购买nft
    function buy(address _from, uint256 _tokenId) public payable{
        nftDAO.buy.value(msg.value)(_from,_tokenId);
        emit Transfer(_from, msg.sender, _tokenId);
    }
    //根据指定地址和索引获取nft
    function tokenOfOwnerByIndex(address _owner, uint256 _index) public view returns (uint){
        return nftDAO.tokenOfOwnerByIndex(_owner, _index);
    }
    //根据nft唯一标识获取meta
    function tokenMetadata(uint256 _tokenId) public view returns (address, string memory, string memory, 
    string memory, uint, uint256, uint256){
        return nftDAO.tokenMetadata(_tokenId);
    }
    //根据nft唯一标识获取nft许可信息
    function tokenAllowInfo(uint256 _tokenId, uint256 _index) public view returns (address, string memory, string memory, 
    uint, uint256, uint256, uint256) {
        return nftDAO.tokenAllowInfo(_tokenId,_index);
    }
    //根据地址获取nft许可信息
    function addressAllowInfo(address _owner, uint256 _index) public view returns (address, string memory, string memory, 
    uint, uint256, uint256, uint256){
        return nftDAO.addressAllowInfo(_owner,_index);
    }
    //获取通证名称
    function name() public view returns (string memory){
        return nftDAO.name();
    }
    //获取通证代号
    function symbol() public view returns (string memory) {
        return nftDAO.symbol();
    }
    //获取多部门签名地址 数组下标为部门编号
    function getSignAddress(uint _no) public view returns (address){
        return nftDAO.getSignAddress(_no);
    }
    //获取外部合约可调用地址
    function isContractAddress(address _address) public view returns (bool){
        return nftDAO.isContractAddress(_address);
    }
    //获取nft部门签名 
    function getNftSign(uint256 _tokenId, uint _no) public view returns (address){
        return nftDAO.getNftSign(_tokenId,_no);
    }
    //获取nft销售和许可价格
    function getPrice(uint256 _tokenId,uint _index) public view returns (uint256){
        return nftDAO.getPrice(_tokenId,_index);
    }
    //获取交易和分成费率
    function getRate() public view returns (uint, uint){
        return nftDAO.getRate();
    }
    //获取nft铸造手续费
    function getFee(uint _index) public view returns (uint256){
        return nftDAO.getFee(_index);
    }
    event Event(bool _allow);
    event Mint(address indexed _mint,uint256 _tokenId);
    event Transfer(address indexed _from, address indexed _to, uint256 _tokenId);
    event Approval(address indexed _owner, address indexed _approved, uint256 _tokenId);
}