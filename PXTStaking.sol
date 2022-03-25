pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./PxswapFactory.sol";

contract PXTStaking is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public pxt;

    struct UserInfo {
        uint amount;
        mapping(uint => uint) rewardDebt;
    }

    struct PoolInfo {
        IERC20 rewardToken;
        uint lastAmount;
        uint newIncome;
        uint totalIncome;
        uint accTokenPerShare;
        uint minHoldRequest;
    }

    PoolInfo[] public poolInfo;

    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function addPool(IERC20 rewardToken, uint minHoldRequest, bool update) external onlyOwner {
        if (update) {
            massUpdatePools();
        }
        poolInfo.push(PoolInfo({
        rewardToken : rewardToken,
        lastAmount : 0,
        totalIncome : 0,
        accTokenPerShare : 0,
        minHoldRequest : minHoldRequest
        }));
    }

    function setPoolInfo(uint pid, uint minHoldRequest) external onlyOwner {
        poolInfo[pid].minHoldRequest = minHoldRequest;
    }

    function poolLength() public returns (uint) {return poolInfo.length;}

    function updatePool(uint pid) public {
        uint pxSupply = pxt.balanceOf(address(this));
        uint curBalance = poolInfo[pid].rewardToken.balanceOf(address(this));
        uint newIncome;
        if (curBalance > poolInfo[pid].lastAmount) {
            newIncome = curBalance - poolInfo[pid].lastAmount;
        }
        poolInfo[pid].lastAmount = curBalance;
        poolInfo[pid].accTokenPerShare = poolInfo[pid].accTokenPerShare + (newIncome * 1e12 / pxSupply);
    }

    function withdraw(uint pid, uint value) external {
        UserInfo storage user = userInfo[msg.sender];
        PoolInfo storage pool = poolInfo[pid];
        updatePool(pid);

        if (user.amount > 0) {
            uint pending = pool.accTokenPerShare * user.amount / 1e12 - user.rewardDebt[pid];
            if (pending > 0) {
                if(pid != 0) {
                    require(pool.rewardToken.balanceOf(msg.sender) >= pool.minHoldRequest, "Less Holding Reward Balance");
                }
                pool.rewardToken.safeTransfer(msg.sender, pending);
            }
        }
        if (value > 0) {
            user.amount -= value;
            pxt.safeTransfer(msg.sender, value);
        }
        user.rewardDebt[pid] = pool.accTokenPerShare * user.amount / 1e12;
        emit Withdraw(msg.sender, pid, value);
    }

    function deposit(uint value) external {

        UserInfo storage user = userInfo[msg.sender];
        uint pid = 0;
        uint bal;
        updatePool(pid);

        if (user.amount > 0) {
            uint pending = poolInfo[pid].accTokenPerShare * user.amount / 1e12 - user.rewardDebt[pid];
            if (pending > 0) {
                poolInfo[pid].rewardToken.safeTransfer(msg.sender, pending);
            }
        }
        if (value > 0) {
            bal = pxt.balanceOf(address(this));
            pxt.safeTransferFrom(msg.sender, address(this), value);
            bal -= pxt.balanceOf(address(this));
            user.amount += bal;
        }
        user.rewardDebt[pid] = poolInfo[pid].accTokenPerShare * user.amount / 1e12;
        emit Deposit(msg.sender, pid, bal);
    }

    function emergencyWithdraw(uint256 pid) public {
        UserInfo storage user = userInfo[msg.sender];
        pxt.safeTransfer(msg.sender, user.amount);
        emit EmergencyWithdraw(msg.sender, pid, user.amount);
        user.amount = 0;
        for(uint i = 0; i < poolInfo.length; i++) {
            user.rewardDebt[i] = 0;
        }
    }


    function pendingReward(uint pid, address account) external view returns (uint) {
        UserInfo storage user = userInfo[account];

        uint pxSupply = pxt.balanceOf(address(this));
        uint curBalance = poolInfo[pid].rewardToken.balanceOf(address(this));
        uint newIncome;
        if (curBalance > poolInfo[pid].lastAmount) {
            newIncome = curBalance - poolInfo[pid].lastAmount;
        }
        uint accPerShare = poolInfo[pid].accTokenPerShare + (newIncome * 1e12 / pxSupply);

        return user.amount * accPerShare / 1e12 - user.rewardDebt[pid];
    }
}
