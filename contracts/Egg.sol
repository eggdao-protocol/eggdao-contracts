// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./ERC20Extends.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IUinSwapFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniSwapRouter {
    function factory() external pure returns (address);
}

interface IEggBroker {
    function _processBuyExchangeFee(address to, uint256 amount) external returns (uint256 exchangeBuyFee);

    function _processStandardTransferFee(address to, uint256 amount) external;
}

interface IEggMebLPDeposit {
    function award(uint256 amount) external returns (bool);
}

contract Egg is ERC20, Ownable {
    using SafeMath for uint8;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public usdtTokenAddress;
    address public mebTokenAddress;
    address public mebUsdtPairAddress;
    address public eggMebPairAddress;

    address public swapRouterAddress;
    address public eggBrokerAddress;

    EnumerableSet.AddressSet private pairAddressSet;

    uint256 public maxUsdtValuePerTransactionLimit = 1000 * 10**18;
    uint256 public maxBalancePerAddressLimit = 500_0000 * 10**18;
    uint256 public maxMebWorthPerAddressLimit = 2000 * 10**18;

    bool public onlyWhiteListSwitch;
    mapping(address => bool) whitelist;

    mapping(address => bool) private freeFeeAccounts;

    uint8 exchangeBuyRate = 15;
    uint8 exchangeSellRate = 5;
    uint8 standardTransferRate = 5;

    uint8 mDaoTreasuryRate = 2;
    address public mDaoTreasuryAddress;

    uint8 globalRewardRate = 3;
    address public globalRewardAddress;

    uint8 lpHoldersBuyRate = 1;
    uint8 lpHoldersSellRate = 2;
    address public lpHoldersAddress;

    uint8 eggDaoTreasuryRate = 1;
    address public eggDaoTreasuryAddress;

    uint8 eggBrokerRate = 11;

    constructor() ERC20("EGG0402-0", "EGG0402-0") {
        _mint(msg.sender, 10_0000_0000 * 10**18);

        IUniSwapRouter uinSwapRouter = IUniSwapRouter(swapRouterAddress);
        eggMebPairAddress = IUinSwapFactory(uinSwapRouter.factory()).createPair(address(this), mebTokenAddress);
        pairAddressSet.add(eggMebPairAddress);

        freeFeeAccounts[msg.sender] = true;
        freeFeeAccounts[address(this)] = true;
        freeFeeAccounts[swapRouterAddress] = true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!onlyWhiteListSwitch || whitelist[from] || whitelist[to], "WhiteList Only");
        require(this.balanceOf(to).add(amount) <= maxBalancePerAddressLimit || freeFeeAccounts[from] || freeFeeAccounts[to] || pairAddressSet.contains(to), "The limit of a single account balance is exceeded");
        if (freeFeeAccounts[from] || freeFeeAccounts[to]) {
            super._transfer(from, to, amount);
        } else if (pairAddressSet.contains(from)) {
            require(!onlyWhiteListSwitch || (this.balanceOf(to).add(amount)).mul(getEggToMebPrice()).div(1e18) <= maxMebWorthPerAddressLimit, "The limit of max meb worth is exceeded");
            require(amount.mul(getEggToMebPrice()).div(1e18).mul(getMebToUsdtPrice()).div(1e18) < maxUsdtValuePerTransactionLimit, "The limit of a single transaction is exceeded");
            super._transfer(from, to, amount);
            uint256 exchangeBuyFee = amount.mul(exchangeBuyRate).div(100);

            uint256 eggBrokerFee = amount.mul(eggBrokerRate).div(100);
            uint256 mDaoTreasuryAmount = IEggBroker(eggBrokerAddress)._processBuyExchangeFee(to, eggBrokerFee);
            eggBrokerFee = eggBrokerFee.sub(mDaoTreasuryAmount);

            uint256 lpHoldersBuyFee = exchangeBuyFee.mul(lpHoldersBuyRate).div(exchangeBuyRate);
            uint256 globalRewardFee = exchangeBuyFee.mul(globalRewardRate).div(exchangeBuyRate);

            bool result = IEggMebLPDeposit(lpHoldersAddress).award(lpHoldersBuyFee);
            if (result) {
                super._takeOutExchangeBuyFee(to, lpHoldersAddress, lpHoldersBuyFee);
            } else {
                mDaoTreasuryAmount = mDaoTreasuryAmount.add(lpHoldersBuyFee);
            }
            super._takeOutExchangeBuyFee(to, eggBrokerAddress, eggBrokerFee);
            super._takeOutExchangeBuyFee(to, mDaoTreasuryAddress, mDaoTreasuryAmount);
            super._takeOutExchangeBuyFee(to, globalRewardAddress, globalRewardFee);
        } else if (pairAddressSet.contains(to)) {
            require(amount.mul(getEggToMebPrice()).div(1e18).mul(getMebToUsdtPrice()).div(1e18) < maxUsdtValuePerTransactionLimit, "The limit of a single transaction is exceeded");
            uint256 exchangeSellFee = amount.mul(exchangeSellRate).div(100);
            amount = amount.sub(exchangeSellFee);

            uint256 mDaoTreasuryFee = exchangeSellFee.mul(mDaoTreasuryRate).div(exchangeSellRate);
            uint256 lpHoldersSellFee = exchangeSellFee.mul(lpHoldersSellRate).div(exchangeSellRate);
            uint256 eggDaoTreasuryFee = exchangeSellFee.mul(eggDaoTreasuryRate).div(exchangeSellRate);

            super._transfer(from, to, amount);
            bool result2 = IEggMebLPDeposit(lpHoldersAddress).award(lpHoldersSellFee);
            if (result2) {
                super._transfer(from, lpHoldersAddress, lpHoldersSellFee);
                super._transfer(from, mDaoTreasuryAddress, mDaoTreasuryFee);
            } else {
                super._transfer(from, mDaoTreasuryAddress, mDaoTreasuryFee.add(lpHoldersSellFee));
            }
            super._transfer(from, eggDaoTreasuryAddress, eggDaoTreasuryFee);
        } else {
            uint256 standardTransferFee = amount.mul(standardTransferRate).div(100);
            amount = amount.sub(standardTransferFee);
            super._transfer(from, eggBrokerAddress, standardTransferFee);
            super._transfer(from, to, amount);
            IEggBroker(eggBrokerAddress)._processStandardTransferFee(to, standardTransferFee);
        }
    }

    function setOnlyWhiteListSwitch(bool _bool) public onlyOwner {
        onlyWhiteListSwitch = _bool;
    }

    function setWhiteList(address _address, bool _bool) public onlyOwner {
        whitelist[_address] = _bool;
    }
    
    function setWhiteListBatch(address[] calldata _address, bool _bool) public onlyOwner {
        for (uint256 i = 0; i < _address.length; i++) {
            whitelist[_address[i]] = _bool;
        }
    }

    function addPairAddress(address _pairAddress) public onlyOwner {
        pairAddressSet.add(_pairAddress);
    }

    function removePairAddress(address _pairAddress) public onlyOwner {
        pairAddressSet.remove(_pairAddress);
    }

    function allPairAddress() public view returns (address[] memory) {
        return pairAddressSet.values();
    }

    function setMaxAmountMebPerTransactionLimit(uint256 _amount) public onlyOwner {
        maxUsdtValuePerTransactionLimit = _amount;
    }

    function setMaxAmountPerAddressLimit(uint256 _amount) public onlyOwner {
        maxBalancePerAddressLimit = _amount;
    }
    
    function setMaxMebWorthPerAddressLimit(uint256 _amount) public onlyOwner {
        maxMebWorthPerAddressLimit = _amount;
    }

    function seEggBrokerAddress(address _address) public onlyOwner {
        eggBrokerAddress = _address;
        freeFeeAccounts[_address] = true;
    }

    function setLpHoldersAddress(address _addr) public onlyOwner {
        lpHoldersAddress = _addr;
    }

    function setMDaoTreasuryAddress(address _addr) public onlyOwner {
        mDaoTreasuryAddress = _addr;
    }

    function setEggDaoTreasuryAddress(address _addr) public onlyOwner {
        eggDaoTreasuryAddress = _addr;
    }

    function setGlobalRewardAddress(address _addr) public onlyOwner {
        globalRewardAddress = _addr;
    }

    function getEggToMebPrice() public view returns (uint256) {
        uint256 mebPairBalance = IERC20(mebTokenAddress).balanceOf(eggMebPairAddress);
        uint256 uCashPairBalance = this.balanceOf(eggMebPairAddress);
        return mebPairBalance.mul(10**18).div(uCashPairBalance);
    }

    function getMebToUsdtPrice() public view returns (uint256) {
        uint256 mebPairBalance = IERC20(mebTokenAddress).balanceOf(mebUsdtPairAddress);
        uint256 usdtPairBalance = IERC20(usdtTokenAddress).balanceOf(mebUsdtPairAddress);
        return usdtPairBalance.mul(10**18).div(mebPairBalance);
    }
}
