// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract EggMebLPDeposit is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public egg;
    address public eggMebPair;

    mapping(address => uint256) public userAmount;
    mapping(address => uint256) public userDebt;
    mapping(address => uint256) public userValid;
    mapping(address => uint256) public userTotalReward;

    uint256 public accAwardPerShare;
    uint256 public totalLpAmount;

    function init(address _egg, address _eggMebPair) public onlyOwner {
        egg = _egg;
        eggMebPair = _eggMebPair;
    }

    function award(uint256 amount) external returns (bool) {
        require(msg.sender == egg, "Forbidden!");
        if (totalLpAmount != 0) {
            accAwardPerShare = accAwardPerShare.add(amount.mul(1e18).div(totalLpAmount));
            return true;
        } else {
            return false;
        }
    }

    function deposit(uint256 amount) public {
        IERC20(eggMebPair).safeTransferFrom(msg.sender, address(this), amount);
        userAmount[msg.sender] = userAmount[msg.sender].add(amount);
        userDebt[msg.sender] = userDebt[msg.sender].add(amount.mul(accAwardPerShare).div(1e18));
        totalLpAmount = totalLpAmount.add(amount);
    }

    function withdraw(uint256 amount) public {
        require(amount <= userAmount[msg.sender], "Insufficient Balance");
        userValid[msg.sender] = pedding(msg.sender);
        userAmount[msg.sender] = userAmount[msg.sender].sub(amount);
        userDebt[msg.sender] = userDebt[msg.sender].sub(amount.mul(accAwardPerShare).div(1e18));
        totalLpAmount = totalLpAmount.sub(amount);
        IERC20(eggMebPair).safeTransfer(msg.sender, amount);
    }

    function harvest() public {
        uint256 _pedding = pedding(msg.sender);
        userDebt[msg.sender] = userDebt[msg.sender].add(_pedding);
        if (userValid[msg.sender] > 0) {
            _pedding = _pedding.add(userValid[msg.sender]);
        }
        if (_pedding > 0) {
            userTotalReward[msg.sender] = userTotalReward[msg.sender].add(_pedding);
            IERC20(egg).safeTransfer(msg.sender, _pedding);
        }
    }

    function pedding(address _addr) public view returns (uint256) {
        return userAmount[_addr].mul(accAwardPerShare).div(1e18).sub(userDebt[_addr]);
    }
}
