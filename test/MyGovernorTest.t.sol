// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {Box} from "../src/Box.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    GovToken govToken;
    TimeLock timeLock;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    address[] proposers;
    address[] executors;

    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    uint256 public constant MIN_DELAY = 1 hours;
    uint256 public constant VOTING_DELAY = 1 days; // how many blocks till a vote is active (1 day)
    uint256 public constant VOTING_PERIOD = 1 weeks; // how many blocks till a vote is active (1 week)

    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        govToken.delegate(USER); // delegate the voting power to USER (self-delegation)
        timeLock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(govToken, timeLock);

        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();
        bytes32 adminRole = timeLock.DEFAULT_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(governor)); // Governor is a proposer
        timeLock.grantRole(executorRole, address(0)); // allow anyone to execute
        timeLock.revokeRole(adminRole, USER); // renounce admin role
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timeLock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(42);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 888;
        string memory description = "Store 888 in the Box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        // 1. Propose to the DAO
        // vm.startPrank(USER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // View the state
        console.log("Proposal ID:", proposalId);
        console.log("Proposal State (Pending=0):", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal State (Active=1):", uint256(governor.state(proposalId)));

        // 2. Vote
        string memory voteReason = "Because eights are great.";
        uint8 voteWay = 1; // 0 = Against, 1 = For, 2 = Abstain

        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, voteReason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. Queue
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);

        vm.stopPrank();

        // Check that the Box was updated
        uint256 storedNumber = box.getNumber();
        console.log("Box number:", storedNumber);
        assertEq(storedNumber, valueToStore);
    }
}
