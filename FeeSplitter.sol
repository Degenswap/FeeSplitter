// SPDX-License-Identifier: No License (None)
pragma solidity ^0.8.0;

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface ISwap {
    function claimFee() external returns (uint256); // returns feeAmount
    function getColletedFees() external view returns (uint256); // returns feeAmount
}

interface IRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

contract FeeSplitter is Ownable {
    using TransferHelper for address;

    address constant public WETH = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c); // WBNB on BSC mainnet
    //address constant public WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH on ETH mainnet

    struct Project {
        address token;
        address company;
        uint256 companyPercentage;  // 20 means 20%
    }

    IRouter public router;
    address public system;
    mapping(address => Project) public projects; // contract address => company wallet
    uint256 public claimGasCost = 200000;    // gas cost to call function claimFeeFrom()

    modifier onlySystem() {
        require(system == msg.sender, "Ownable: caller is not the owner");
        _;        
    }

    function setSystem(address _system) external onlyOwner {
        require(_system != address(0));
        system = _system;
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0));
        router = IRouter(_router);
    }

 
    // set gas cost to call function claimFeeFrom()
    // (call function claimFeeFrom(), check how much gas it used and set this value as gasCost)
    function setClaimGasCost(uint256 gasCost) external onlyOwner {
        require(gasCost < 2000000);
        claimGasCost = gasCost;
    }

    // set project related data
    function setCompanyWallet(
        address project, // project contract address where should be called claimFee()
        address token, // project token, that should be bought using fee
        address company, // company wallet address that should receive part of fee
        uint256 percentage // part of fee that should be send to company wallet (i.e. 20 = 20%)
    ) external onlyOwner 
    {
        require(company != address(0) && token != address(0) && percentage <= 100);
        projects[project].token = token;
        projects[project].company = company;
        projects[project].companyPercentage = percentage;
    }


    // get estimate value of project tokens that will be received from selling fees.
    // use result of this function for calculating "amountOutMin" parameter of function claimFeeFrom()
    function getEstimateAmountOut(address project) external view returns(uint256 amountOut) {
        uint256 gasFee = claimGasCost * tx.gasprice;
        Project memory p = projects[project];
        require(p.token != address(0), "Wrong project address");
        uint256 fee = ISwap(project).getColletedFees() - gasFee;
        uint256 companyPart = fee * p.companyPercentage / 100;
        fee = fee - companyPart;
        if (fee != 0) {
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = p.token;
            uint256[] memory amounts = router.getAmountsOut(fee, path);
            amountOut = amounts[1];
        }
    }

    // claim fee from project and push it to pool
    // amountOutMin min amount to receive (i.e: amountOutMin = getEstimateAmountOut() * 99 / 100)
    function claimFeeFrom(
        address project,    // project address to claimFee() from
        uint256 amountOutMin    // minimum amount of project's token that should be received by swapping fee (front running protection)
        ) external onlySystem 
    {
        uint256 gasFee = claimGasCost * tx.gasprice;
        Project memory p = projects[project];
        require(p.token != address(0), "Wrong project address");
        uint256 fee = ISwap(project).claimFee() - gasFee;
        system.safeTransferETH(gasFee); // refund gas fee to the caller.
        uint256 companyPart = fee * p.companyPercentage / 100;
        fee = fee - companyPart;
        if (companyPart != 0) p.company.safeTransferETH(companyPart);
        if (fee != 0) {
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = p.token;
            router.swapExactETHForTokens{value:fee}(amountOutMin, path, address(1), block.timestamp);
        }
    }

    receive() external payable {}

    // If someone accidentally transfer tokens to this contract, the owner will be able to rescue it and refund sender.
    function rescueTokens(address _token) external onlyOwner {
        if (address(0) == _token) {
            payable(msg.sender).transfer(address(this).balance);
        } else {
            uint256 available = IERC20(_token).balanceOf(address(this));
            TransferHelper.safeTransfer(_token, msg.sender, available);
        }
    }
}