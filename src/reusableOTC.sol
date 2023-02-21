pragma solidity ^0.8.16;

interface IERC20 {
    function transfer(address to, uint amount) external;
    function transferFrom(address from, address to, uint amount) external;
    function balanceOf(address holder) external returns(uint);
}

contract ReusableOTC {
    struct Deal {
        address token;
        uint tokenAmount;
        uint invAmount;
        uint deadline;
    }

    IERC20 constant INV = IERC20(0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68);
    address owner;
    mapping(address => Deal) deals;

    constructor(address _owner){
        owner = _owner;
    }

    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }

    function createDeal(address buyer, address token, uint tokenAmount, uint invAmount, uint deadline) external onlyOwner {
        require(block.timestamp < deadline);
        deals[buyer] = Deal(token, tokenAmount, invAmount, deadline);
    }

    function buy(address token, uint tokenAmount, uint invAmount) external {
        Deal memory deal = deals[msg.sender];
        require(block.timestamp <= deal.deadline);
        require(deal.token == token);
        require(deal.tokenAmount == tokenAmount);
        require(deal.invAmount == invAmount);

        uint balBefore = IERC20(token).balanceOf(owner);
        IERC20(token).transferFrom(msg.sender, owner, tokenAmount);
        INV.transferFrom(owner, msg.sender, invAmount);
        
        //Check that our token balance increase by expected amount, just in case the buyer token doesn't fail on insufficient approval
        //No need to check this with INV, as INV will fail
        require(IERC20(token).balanceOf(owner) == balBefore + tokenAmount);

        emit Buy(msg.sender, token, tokenAmount, invAmount);
        //Delete struct to protet against multiple buys
        delete deals[msg.sender];
    }

    function terminate(address buyer) external onlyOwner {
        delete deals[buyer];
    }

    function sweep(address token, address to) external onlyOwner {
        IERC20(token).transfer(to, IERC20(token).balanceOf(address(this)));
    }

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    event Buy(address buyer, address token, uint tokenAmount, uint invAmount);
}
