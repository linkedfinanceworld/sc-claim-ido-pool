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

    // total claimed for each round
    mapping(uint256 => uint256) public totalClaimed;

    // claim token address
    address public claimToken;


    // number of participant has been claimed
    mapping(uint256 => uint256) public claimedCount;

    // allocation amount
    uint256 public roundNumber;

    // Is the pool initialize yet
    bool public isInitilized; 

    // Mapping is claimed for an address at a specific round
    mapping(address => mapping(uint256 => bool)) public isClaimed;

    // user address => pool name => bool.
    mapping(address => mapping(uint256 => bool)) public whitelistAddress;

    // user address => pool name => claimable Token
    mapping(address => mapping(uint256 => uint256)) public claimAbleToken;

    // user address => pool name => claimable Token
    mapping(uint256 => uint256) public claimStartAt;

    event EventClaimed(
        address indexed sender,
        uint256 round,
        uint256 amount,
        uint256 date
    );
    event setToken(address indexed newToken);
    event setClaimTime(uint256 newClaimTime, uint256 round);
    event setClaimAmount(uint256[] newClaimAmount);

    /**
     * @notice set new config for the SC
     * @dev only call by owner
     * @param _token: claim token address
     * @param _roundNumber: round number
     */
    function setConfig(
        address _token,
        uint256 _roundNumber
    ) external onlyOwner {
        require(
            !isInitilized, 
            "Pool is already initilized"
        );

        require(
            _token != address(0), 
            "Invalid address"
        );

        isInitilized = true;
        claimToken = _token;
        roundNumber = _roundNumber;
    }

    /**
     * @notice set new token if needed
     * @dev only call by owner
     */    
    function setNewToken(address _token) external onlyOwner {
        require(
            _token != address(0), 
            "Invalid address"
        );
        claimToken = _token;
        emit setToken(_token);
    }

    /**
     * @notice set new claim time each round if needed
     * @dev only call by owner
     */    
    function setNewClaimTime(
        uint256 _claimTime,
        uint256 _round
    ) external onlyOwner {
        claimStartAt[_round] = _claimTime;
        emit setClaimTime(_claimTime, _round);
    }


    /**
     * @notice whitelist address to pool and update number of slot if existed. Only work for claiming in 4 rounds
     * @dev only call by owner
     * @param _addresses: list whitelist address
     * @param _round: number of round to claim token
     */
    function addWhitelistAddress(
        address[] memory _addresses,
        uint256 _round
    ) external onlyOwner {
        require(isInitilized, "Pool is not initilize");
        for (uint256 index = 0; index < _addresses.length; index++) {
            for (uint256 round = 1; round <= _round; round++) {
                whitelistAddress[_addresses[index]][round] = true;
            }
        }
    }

    /**
     * @notice remove whitelist address
     * @dev only call by owner
     */
    function removeWhitelistAddress(
        address[] memory _addresses,
        uint256 _round
    ) external onlyOwner {
        require(isInitilized, "Pool is not initilize");
        for (uint256 index = 0; index < _addresses.length; index++) {
            for (uint256 round = 1; round <= _round; round++) {
                whitelistAddress[_addresses[index]][round] = false;
            }
        }      
    }

    /**
     * @notice update claimable amount of token for each address in each round
     * @dev only call by owner
     * @param _addresses: list whitelist address
     * @param _amount: amount to claim for each address in a specific round
     * @param _round: round number 
     */
    function addClaimableToken(
        address[] memory _addresses,
        uint256[] memory _amount,
        uint256 _round
    ) external onlyOwner {
        require(
            _addresses.length == _amount.length,
            "Length of addresses and allocation values are different"
        );
        for (uint256 index = 0; index < _addresses.length; index++) {
            claimAbleToken[_addresses[index]][_round] = _amount[index];
        } 
    }

    /**
     * @notice claim button for each round
     * @dev call by external
     * @param _round: vesting round, i.e., 1, 2, 3, etc.
     */
    function claim(uint256 _round) external {
        require(isInitilized, "Pool is not initilize");
        uint256 index = _round;

        require(
            index <= roundNumber,
            "Wrong claim round"
        );

        uint256 claimAble = claimAbleToken[_msgSender()][index];
        uint256 thisBal = IERC20(claimToken).balanceOf(address(this));

        require(
            thisBal >= claimAble,
            "Not enough balance in SC"
        );

        require(
            whitelistAddress[_msgSender()][index], 
            "You are not whitelisted or have already claimed token"
        );

        require(
            claimStartAt[index] > 0 && block.timestamp >= claimStartAt[index],
            'Claim time has not started yet'
        );

        // Setting for FE
        isClaimed[_msgSender()][index] = true;
        totalClaimed[index] += claimAble;
        claimedCount[index] += 1;

        // Transfer token from SC to user
        IERC20(claimToken).safeTransfer(_msgSender(), claimAble);
        
        // Remove from whitelist at n-th round
        whitelistAddress[_msgSender()][index] = false;
        
        // Remove from claimable Token list at n-th round
        claimAbleToken[_msgSender()][index] = 0;

        // Claimed event
        emit EventClaimed(
            _msgSender(),
            index,
            claimAble,
            block.timestamp
        );
    }

    /*
     * @notice Withdraw staked tokens without caring about rewards rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw(uint256 _amount) external onlyOwner {
        ERC20(claimToken).transfer(address(msg.sender), _amount);
    }

}