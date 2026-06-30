// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract ChallengeToken is ERC20 {
    address public immutable factory;
    uint256 public immutable challengeId;

    constructor(
        string memory _name,
        string memory _symbol,
        address _factory,
        uint256 _challengeId
    ) ERC20(_name, _symbol) {
        factory = _factory;
        challengeId = _challengeId;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    function mint(address to, uint256 amount) external onlyFactory {
        _mint(to, amount);
    }
}

contract ChallengeBadge is ERC721, Ownable {
    uint256 public nextTokenId;
    mapping(uint256 => uint256) public challengeIdOfToken;
    mapping(uint256 => uint256) public tokenIdOfChallengeWinner;

    constructor(address _owner) ERC721("BaseDrop Badge", "BDB") Ownable(_owner) {}

    function mintWinner(uint256 _challengeId, address _winner) external onlyOwner returns (uint256) {
        require(tokenIdOfChallengeWinner[_challengeId] == 0, "Already minted");
        uint256 tokenId = nextTokenId++;
        _mint(_winner, tokenId);
        challengeIdOfToken[tokenId] = _challengeId;
        tokenIdOfChallengeWinner[_challengeId] = tokenId;
        return tokenId;
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = super._update(to, tokenId, auth);
        require(from == address(0) || to == address(0), "Soulbound: non-transferable");
        return from;
    }
}

contract ChallengeFactory is Ownable, ReentrancyGuard {
    struct Challenge {
        uint256 id;
        string title;
        string description;
        uint256 prizePool;
        uint64 deadline;
        uint256 totalMints;
        bool settled;
        address winner;
        address tokenAddress;
    }

    uint256 public challengeCount;
    mapping(uint256 => Challenge) public challenges;
    ChallengeBadge public immutable badge;

    uint256 public constant MINT_PRICE = 0.001 ether;

    event ChallengeCreated(uint256 indexed challengeId, address indexed tokenAddress, string title);
    event ChallengeSettled(uint256 indexed challengeId, address indexed winner, uint256 prizeAmount);
    event Minted(uint256 indexed challengeId, address indexed minter, uint256 amount);

    constructor(address _owner) Ownable(_owner) {
        badge = new ChallengeBadge(address(this));
    }

    function createChallenge(
        string calldata _title,
        string calldata _description,
        uint256 _prizePool,
        uint64 _duration
    ) external payable returns (uint256) {
        require(_duration >= 1 hours && _duration <= 30 days, "Invalid duration");
        require(msg.value >= _prizePool, "Insufficient prize pool");

        uint256 id = ++challengeCount;
        string memory name = string(abi.encodePacked("Challenge #", _uint2str(id)));
        string memory symbol = string(abi.encodePacked("BDROP", _uint2str(id)));

        ChallengeToken token = new ChallengeToken(name, symbol, address(this), id);

        challenges[id] = Challenge({
            id: id,
            title: _title,
            description: _description,
            prizePool: _prizePool,
            deadline: uint64(block.timestamp) + _duration,
            totalMints: 0,
            settled: false,
            winner: address(0),
            tokenAddress: address(token)
        });

        emit ChallengeCreated(id, address(token), _title);
        return id;
    }

    function mintFor(uint256 _challengeId, uint256 _amount) external {
        Challenge storage c = challenges[_challengeId];
        require(block.timestamp < c.deadline, "Challenge ended");
        require(!c.settled, "Already settled");

        ChallengeToken(c.tokenAddress).mint(msg.sender, _amount);
        c.totalMints += _amount;

        emit Minted(_challengeId, msg.sender, _amount);
    }

    function settleChallenge(uint256 _challengeId, address _winner) external onlyOwner nonReentrant {
        Challenge storage c = challenges[_challengeId];
        require(block.timestamp >= c.deadline, "Not ended yet");
        require(!c.settled, "Already settled");
        require(_winner != address(0), "Invalid winner");

        c.settled = true;
        c.winner = _winner;

        badge.mintWinner(_challengeId, _winner);

        uint256 payout = c.prizePool + (c.totalMints * MINT_PRICE);
        (bool success, ) = payable(_winner).call{value: payout}("");
        require(success, "Transfer failed");

        emit ChallengeSettled(_challengeId, _winner, payout);
    }

    function getChallenge(uint256 _challengeId) external view returns (Challenge memory) {
        return challenges[_challengeId];
    }

    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) { len++; j /= 10; }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            bytes1 b1 = bytes1(48 + uint8(_i % 10));
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    receive() external payable {}
}