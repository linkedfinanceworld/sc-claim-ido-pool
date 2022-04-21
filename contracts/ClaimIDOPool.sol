// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ClaimIDOPool is 
        Context,
        Ownable,
        ERC20("LFW Claim IDO Pool", "LFW-IDO-Claim") 
{

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // the token address for IDO Claiming
    address public tokenAddress;

    // total claimed token for each round
    mapping(uint256 => uint256) public claimedTokenAtRound;

    // number of participants who have claimed for each round
    mapping(uint256 => uint256) public claimedUsersAtRound;

    // allocation amount
    uint256 public roundNumber;

    // Is the pool initialize yet
    bool public isInitialized; 

    // If user (address) has claimed at a specific round
    mapping(address => mapping(uint256 => bool)) public isClaimed;

    // If user (address) is whitelisted at a specific round
    mapping(address => mapping(uint256 => bool)) public isAddressWhitelisted;

    // The quota of token that each user (address) can claim at a specific round
    mapping(address => mapping(uint256 => uint256)) public claimQuota;

    // Time that the users can start to claim
    mapping(uint256 => uint256) public claimStartAt;

    event Claim(
        address indexed sender,
        uint256 round,
        uint256 amount,
        uint256 date
    );
    event NewTokenSet(address indexed newToken);
    event ClaimTimeSet(uint256 newClaimTime, uint256 round);


    /**
     * @notice set config for the SC
     * @dev only call by owner
     * @param _token: the token address that will be used for claiming
     * @param _roundNumber: the number of rounds for users to claim
     */
    function setConfig(
        address _token,
        uint256 _roundNumber
    ) external onlyOwner {
        require(
            !isInitialized, 
            "Pool is already initialized"
        );

        require(
            _token != address(0), 
            "Invalid address"
        );

        isInitialized = true;
        tokenAddress = _token;
        roundNumber = _roundNumber;
    }

    /**
     * @notice set new token if needed
     * @dev only call by owner
     * @param _token: the new token address that will be used for claiming
     */    
    function setNewToken(address _token) external onlyOwner {
        require(
            _token != address(0), 
            "Invalid address"
        );
        tokenAddress = _token;
        emit NewTokenSet(_token);
    }

    /**
     * @notice set claim time each round
     * @dev only call by owner
     * @param _claimTime: the time for user to start claiming
     * @param _round: the round is used to set the time
     */    
    function setClaimTime(
        uint256 _claimTime,
        uint256 _round
    ) external onlyOwner {
        claimStartAt[_round] = _claimTime;
        emit ClaimTimeSet(_claimTime, _round);
    }


    /**
     * @notice whitelist a list of addresses for all rounds
     * @dev only call by owner
     * @param _addresses: list of addresses will be whitelisted
     */
    function addWhitelistAddressesForAllRounds(
        address[] memory _addresses
    ) external onlyOwner {
        require(isInitialized, "Pool is not initialized");
        for (uint256 i = 0; i < _addresses.length; i++) {
            for (uint256 round = 1; round <= roundNumber; round++) {
                isAddressWhitelisted[_addresses[i]][round] = true;
            }
        }
    }

    /**
     * @notice whitelist a list of addresses at a specifict round
     * @dev only call by owner
     * @param _addresses: list of addresses will be whitelisted
     * @param _round: number of rounds to claim token
     */
    function addWhitelistAddressesForRound(
        address[] memory _addresses,
        uint256 _round
    ) external onlyOwner {
        require(isInitialized, "Pool is not initialized");
        require(_round <= roundNumber, "Invalid round input");
        for (uint256 i = 0; i < _addresses.length; i++) {
            isAddressWhitelisted[_addresses[i]][_round] = true;
        }
    }


    /**
     * @notice unwhitelist a list of addresses
     * @dev only call by owner
     * @param _addresses: list of addresses will be unwhitelisted
     */
    function removeWhitelistAddresses(
        address[] memory _addresses
    ) external onlyOwner {
        require(isInitialized, "Pool is not initialized");
        for (uint256 i = 0; i < _addresses.length; i++) {
            for (uint256 round = 1; round <= roundNumber; round++) {
                isAddressWhitelisted[_addresses[i]][round] = false;
            }
        }      
    }


    /**
     * @notice whitelist a list of addresses at a specifict round
     * @dev only call by owner
     * @param _addresses: list of addresses will be whitelisted
     * @param _round: number of rounds to claim token
     */
    function removeWhitelistAddressesForRound(
        address[] memory _addresses,
        uint256 _round
    ) external onlyOwner {
        require(isInitialized, "Pool is not initialized");
        require(_round <= roundNumber, "Invalid round input");
        for (uint256 i = 0; i < _addresses.length; i++) {
            isAddressWhitelisted[_addresses[i]][_round] = false;
        }
    }


    /**
     * @notice set quota for each user (address) to claim at a specific round
     * @dev only call by owner
     * @param _addresses: list of user addresses
     * @param _amount: list of token amount for the user addresses to claim accordingly
     * @param _round: round number 
     */
    function setClaimQuota(
        address[] memory _addresses,
        uint256[] memory _amount,
        uint256 _round
    ) external onlyOwner {
        require(
            _addresses.length == _amount.length,
            "Length of addresses and allocation values are different"
        );
        for (uint256 i = 0; i < _addresses.length; i++) {
            claimQuota[_addresses[i]][_round] = _amount[i];
        } 
    }

    /**
     * @notice claim the quota of token at a round
     * @dev call by external
     * @param _round: vesting round, i.e., 1, 2, 3, etc.
     */
    function claim(uint256 _round) external {
        require(isInitialized, "Pool is not initialized");

        require( _round <= roundNumber, "Invalid round input");

        uint256 quota = claimQuota[_msgSender()][_round];
        uint256 poolBalance = IERC20(tokenAddress).balanceOf(address(this));

        require(
            poolBalance >= quota,
            "Insufficient balance in Pool for this claim"
        );

        require(
            isAddressWhitelisted[_msgSender()][_round], 
            "You are not whitelisted or have already claimed token at this round"
        );

        require(
            claimStartAt[_round] > 0 && block.timestamp >= claimStartAt[_round],
            'Claim time has not started yet'
        );

        // Setting for FE
        isClaimed[_msgSender()][_round] = true;
        claimedTokenAtRound[_round] += quota;
        claimedUsersAtRound[_round] += 1;

        // Remove from whitelist at n-th round
        isAddressWhitelisted[_msgSender()][_round] = false;
        
        // Remove from claimable Token list at n-th round
        claimQuota[_msgSender()][_round] = 0;

        // Transfer token from SC to user
        IERC20(tokenAddress).safeTransfer(_msgSender(), quota);
        
        // Claimed event
        emit Claim(
            _msgSender(),
            _round,
            quota,
            block.timestamp
        );
    }

    /*
     * @notice Withdraw staked tokens without caring about rewards rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw(uint256 _amount) external onlyOwner {
        ERC20(tokenAddress).transfer(address(msg.sender), _amount);
    }

}