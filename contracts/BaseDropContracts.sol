// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ChallengeToken {
    string public name;
    string public symbol;
    address public immutable factory;
    uint256 public immutable challengeId;
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(string memory _name, string memory _symbol, address _factory, uint256 _challengeId) {
        name = _name;
        symbol = _symbol;
        factory = _factory;
        challengeId = _challengeId;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    function mint(address to, uint256 amount) external onlyFactory {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

contract ChallengeFactory {
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
    address public owner;

    event ChallengeCreated(uint256 indexed challengeId, address indexed tokenAddress, string title);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
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
            bstr[k] = bytes1(48 + uint8(_i % 10));
            _i /= 10;
        }
        return string(bstr);
    }

    receive() external payable {}
}