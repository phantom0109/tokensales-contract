// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenSales is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  
	/* The start, close, and unlock timestamps of TokenSales */
	uint256 public startTime;
	uint256 public closeTime;
	uint256 public unlockTime;

	/* Fixed price
   * price = reward tokens per invested token (e.g. 1 USDT = 1000 VEGA)
   */
	uint256 constant price = 1000;

	/* Addresses of the token contracts */
	IERC20 private investToken;
  IERC20 private rewardToken;
  
	uint256 constant cap = 120 * (10**18);

	/* how much has been raised by crowdale (in InvestToken) */
	uint256 public totalInvested;
	/* how much has been sold by crowdale (in RewardToken) */
	uint256 public totalRewarded;

  /* Whitelisted investors and their amounts */
  mapping(address => uint256) public whitelist;
	/* Balances (in InvestToken) of all investors */
	mapping(address => uint256) public investedFrom;
  
	/* Notifying transfers and the success of the TokenSales*/
	event CapReached(address lastInvestor, uint256 lastInvestment);
	event Invested(address investor, uint256 amount, uint256 totalInvested);
	event TimestampsUpdated(uint256 startTime, uint256 closeTime, uint256 unlockTime);

  modifier salesInProgress() {
    require(block.timestamp >= startTime, "Sales not started yet");
    require(block.timestamp <= closeTime, "Sales is already closed");
    _;
  }

  modifier unlocked() {
    require(block.timestamp >= unlockTime, "Rewards are not unlocked yet");
    _;
  }

  modifier whitelisted() {
    require(whitelist[msg.sender] > 0, "You are not whitelisted to invest");
    _;
  }

  /*  initialization, set the token address */
  constructor(address _investToken, address _rewardToken, uint256 _startTime, uint256 _closeTime, uint256 _unlockTime) {
    investToken = IERC20(_investToken);
    rewardToken = IERC20(_rewardToken);
    startTime = _startTime;
    closeTime = _closeTime;
    unlockTime = _unlockTime;
  }

	function updateTimestamps(uint256 _startTime, uint256 _closeTime, uint256 _unlockTime) external onlyOwner {
    startTime = _startTime;
    closeTime = _closeTime;
    unlockTime = _unlockTime;
    emit TimestampsUpdated(startTime, closeTime, unlockTime);
	}

  function addWhitelist(address[] memory investors, uint256[] memory amounts) external onlyOwner {

    require(investors.length == amounts.length, "Addresses and amounts array lengths must match");

    for (uint256 i = 0; i < investors.length; i++) {
        address addr = investors[i];
        whitelist[addr] = amounts[i];
    }
  }
  
  /* Make an investment
  *  only callable if the TokenSales started and hasn't been closed already and the maxGoal wasn't reached yet.
  *  the current token price is looked up and the corresponding number of tokens is transfered to the receiver.
  *  the sent value is directly forwarded to a safe multisig wallet.
  *  this method allows to purchase tokens in behalf of another address.*/
  function invest(uint256 amount) external salesInProgress whitelisted {
    
    require(amount > 0, "Zero investment");
    require(amount == whitelist[msg.sender], "Invest amount is not equal to the whitelist amount");
    require(investedFrom[msg.sender] == 0, "You already invested");
    require(totalInvested.add(amount) <= cap, "VegaIDO: Cap for current round reached");

    investedFrom[msg.sender] = amount;

    totalInvested = totalInvested.add(amount);
    totalRewarded = totalRewarded.add(amount.mul(price));

    if (totalInvested >= cap) {
      // Trigger an event with last investor
      emit CapReached(msg.sender, amount);
    }
    
    emit Invested(msg.sender, amount, totalInvested);
  }

	function claimReward() external whitelisted unlocked nonReentrant {

		require(investedFrom[msg.sender] > 0, "non-contribution");

		uint256 amount = investedFrom[msg.sender].mul(price);
		uint256 balance = rewardToken.balanceOf(address(this));
		require(balance >= amount, "Lack of funds");

		investedFrom[msg.sender] = 0;
		rewardToken.transfer(msg.sender, amount);
	}

	function withdrawRaisedFunds() external onlyOwner {
		uint256 balance = investToken.balanceOf(address(this));
    // balance must be equal to totalInvested
		require(balance > 0, "Zero fund raised");
		investToken.transfer(msg.sender, balance);
	}

	function withdrawRewardsLeft() external onlyOwner {
		uint256 balance = rewardToken.balanceOf(address(this));
		require(balance > 0, "Zero fund left");
		rewardToken.transfer(msg.sender, balance);
	}
}