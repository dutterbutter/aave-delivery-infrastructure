// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OwnableWithGuardian, IWithGuardian} from 'solidity-utils/contracts/access-control/OwnableWithGuardian.sol';
import {GovernanceV3Polygon} from 'aave-address-book/GovernanceV3Polygon.sol';
import {MiscPolygon} from 'aave-address-book/MiscPolygon.sol';
import {TestUtils} from '../utils/TestUtils.sol';
import '../../src/contracts/access_control/GranularGuardianAccessControl.sol';
import '../BaseTest.sol';

contract GranularGuardianAccessControlIntTest is BaseTest {
  bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
  address public constant BGD_GUARDIAN = 0xbCEB4f363f2666E2E8E430806F37e97C405c130b;

  // list of supported chains
  uint256 destinationChainId = ChainIds.ETHEREUM;

  GranularGuardianAccessControl public control;
  address public ccc;

  modifier createGGAC(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian
  ) {
    vm.assume(retryGuardian != address(this));
    vm.assume(defaultAdmin != address(this));
    vm.assume(solveEmergencyGuardian != address(this));
    _filterAddress(defaultAdmin);
    _filterAddress(retryGuardian);
    _filterAddress(solveEmergencyGuardian);

    IGranularGuardianAccessControl.InitialGuardians
      memory initialGuardians = IGranularGuardianAccessControl.InitialGuardians({
        defaultAdmin: defaultAdmin,
        retryGuardian: retryGuardian,
        solveEmergencyGuardian: solveEmergencyGuardian
      });
    control = new GranularGuardianAccessControl(
      initialGuardians,
      GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER
    );

    OwnableWithGuardian(GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER).updateGuardian(
      address(control)
    );
    _;
  }

  function setUp() public {
    vm.createSelectFork('polygon', 58315066);
  }

  function test_initialization(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian
  ) public createGGAC(defaultAdmin, retryGuardian, solveEmergencyGuardian) {
    assertEq(control.CROSS_CHAIN_CONTROLLER(), GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER);
    assertEq(control.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
    assertEq(control.getRoleAdmin(control.RETRY_ROLE()), DEFAULT_ADMIN_ROLE);
    assertEq(control.getRoleAdmin(control.SOLVE_EMERGENCY_ROLE()), DEFAULT_ADMIN_ROLE);
    assertEq(control.getRoleMemberCount(control.RETRY_ROLE()), 1);
    assertEq(control.getRoleMemberCount(control.SOLVE_EMERGENCY_ROLE()), 1);
    assertEq(control.getRoleMember(control.RETRY_ROLE(), 0), retryGuardian);
    assertEq(control.getRoleMember(control.SOLVE_EMERGENCY_ROLE(), 0), solveEmergencyGuardian);
  }

  function test_retryTx(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian,
    address destination,
    uint256 gasLimit
  )
    public
    createGGAC(defaultAdmin, retryGuardian, solveEmergencyGuardian)
    generateRetryTxState(
      GovernanceV3Polygon.EXECUTOR_LVL_1,
      GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER,
      destinationChainId,
      destination,
      gasLimit
    )
  {
    _retryTx(destination, retryGuardian, gasLimit);
  }

  function _retryTx(address destination, address retryGuardian, uint256 gasLimit) internal {
    ExtendedTransaction memory extendedTx = _generateExtendedTransaction(
      TestParams({
        destination: destination,
        origin: address(this),
        originChainId: block.chainid,
        destinationChainId: destinationChainId,
        envelopeNonce: ICrossChainForwarder(GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER)
          .getCurrentTransactionNonce() - 1,
        transactionNonce: ICrossChainForwarder(GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER)
          .getCurrentTransactionNonce() - 1
      })
    );

    ICrossChainForwarder.ChainIdBridgeConfig[] memory bridgeAdaptersByChain = ICrossChainForwarder(
      GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER
    ).getForwarderBridgeAdaptersByChain(1);
    address[] memory bridgeAdaptersToRetry = new address[](1);
    bridgeAdaptersToRetry[0] = bridgeAdaptersByChain[0].currentChainBridgeAdapter;

    vm.startPrank(retryGuardian);
    control.retryTransaction(extendedTx.transactionEncoded, gasLimit, bridgeAdaptersToRetry);
    vm.stopPrank();
  }

  function test_retryTxWhenWrongCaller(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian,
    uint256 gasLimit,
    address caller
  ) public createGGAC(defaultAdmin, retryGuardian, solveEmergencyGuardian) {
    address[] memory bridgeAdaptersToRetry = new address[](0);
    vm.assume(caller != retryGuardian);

    hoax(caller);
    vm.expectRevert(
      bytes(
        string.concat(
          'AccessControl: account 0x',
          TestUtils.toAsciiString(caller),
          ' is missing role 0xc448b9502bbdf9850cc39823b6ea40cfe96d3ac63008e89edd2b8e98c6cc0af3'
        )
      )
    );

    control.retryTransaction(abi.encode('will not get used'), gasLimit, bridgeAdaptersToRetry);
  }

  function test_retryEnvelope(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian,
    address destination,
    uint256 gasLimit
  )
    public
    createGGAC(defaultAdmin, retryGuardian, solveEmergencyGuardian)
    generateRetryTxState(
      GovernanceV3Polygon.EXECUTOR_LVL_1,
      GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER,
      destinationChainId,
      destination,
      gasLimit
    )
  {
    _retryEnvelope(destination, retryGuardian, gasLimit);
  }

  function _retryEnvelope(address destination, address retryGuardian, uint256 gasLimit) internal {
    uint256 envNonce = ICrossChainForwarder(GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER)
      .getCurrentEnvelopeNonce() - 1;

    ExtendedTransaction memory extendedTx = _generateExtendedTransaction(
      TestParams({
        destination: destination,
        origin: address(this),
        originChainId: block.chainid,
        destinationChainId: destinationChainId,
        envelopeNonce: envNonce,
        transactionNonce: ICrossChainForwarder(GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER)
          .getCurrentTransactionNonce() - 1
      })
    );

    vm.startPrank(retryGuardian);
    bytes32 newTxId = control.retryEnvelope(extendedTx.envelope, gasLimit);

    ExtendedTransaction memory extendedTxAfter = _generateExtendedTransaction(
      TestParams({
        destination: destination,
        origin: address(this),
        originChainId: block.chainid,
        destinationChainId: destinationChainId,
        envelopeNonce: envNonce,
        transactionNonce: ICrossChainForwarder(GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER)
          .getCurrentTransactionNonce() - 1
      })
    );

    assertEq(extendedTxAfter.transactionId, newTxId);
    vm.stopPrank();
  }

  function test_retryEnvelopeWhenWrongCaller(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian,
    uint256 gasLimit,
    address caller
  ) public createGGAC(defaultAdmin, retryGuardian, solveEmergencyGuardian) {
    vm.assume(caller != retryGuardian);

    Envelope memory envelope;

    hoax(caller);
    vm.expectRevert(
      bytes(
        string.concat(
          'AccessControl: account 0x',
          TestUtils.toAsciiString(caller),
          ' is missing role 0xc448b9502bbdf9850cc39823b6ea40cfe96d3ac63008e89edd2b8e98c6cc0af3'
        )
      )
    );
    control.retryEnvelope(envelope, gasLimit);
  }

  function test_solveEmergency(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian
  )
    public
    createGGAC(defaultAdmin, retryGuardian, solveEmergencyGuardian)
    generateEmergencyState(GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER)
    validateEmergencySolved(GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER)
  {
    vm.startPrank(solveEmergencyGuardian);
    vm.expectRevert(bytes(''));
    control.solveEmergency(
      new ICrossChainReceiver.ConfirmationInput[](0),
      new ICrossChainReceiver.ValidityTimestampInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new address[](0),
      new address[](0),
      new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](0),
      new ICrossChainForwarder.BridgeAdapterToDisable[](0),
      new ICrossChainForwarder.OptimalBandwidthByChain[](0)
    );
    vm.stopPrank();
  }

  function test_solveEmergencyOld(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian
  )
    public
    createGGAC(defaultAdmin, retryGuardian, solveEmergencyGuardian)
    generateEmergencyState(GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER)
    validateEmergencySolved(GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER)
  {
    vm.startPrank(solveEmergencyGuardian);
    control.solveEmergencyRev2(
      new ICrossChainReceiver.ConfirmationInput[](0),
      new ICrossChainReceiver.ValidityTimestampInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new address[](0),
      new address[](0),
      new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](0),
      new ICrossChainForwarder.BridgeAdapterToDisable[](0)
    );
    vm.stopPrank();
  }

  function test_solveEmergencyWhenWrongCaller(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian,
    address caller
  ) public createGGAC(defaultAdmin, retryGuardian, solveEmergencyGuardian) {
    vm.assume(caller != solveEmergencyGuardian);
    hoax(caller);
    vm.expectRevert(
      bytes(
        string.concat(
          'AccessControl: account 0x',
          TestUtils.toAsciiString(caller),
          ' is missing role 0xf4cdc679c22cbf47d6de8e836ce79ffdae51f38408dcde3f0645de7634fa607d'
        )
      )
    );
    control.solveEmergency(
      new ICrossChainReceiver.ConfirmationInput[](0),
      new ICrossChainReceiver.ValidityTimestampInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new address[](0),
      new address[](0),
      new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](0),
      new ICrossChainForwarder.BridgeAdapterToDisable[](0),
      new ICrossChainForwarder.OptimalBandwidthByChain[](0)
    );
  }

  function test_solveEmergencyRev2WhenWrongCaller(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian,
    address caller
  ) public createGGAC(defaultAdmin, retryGuardian, solveEmergencyGuardian) {
    vm.assume(caller != solveEmergencyGuardian);
    hoax(caller);
    vm.expectRevert(
      bytes(
        string.concat(
          'AccessControl: account 0x',
          TestUtils.toAsciiString(caller),
          ' is missing role 0xf4cdc679c22cbf47d6de8e836ce79ffdae51f38408dcde3f0645de7634fa607d'
        )
      )
    );
    control.solveEmergencyRev2(
      new ICrossChainReceiver.ConfirmationInput[](0),
      new ICrossChainReceiver.ValidityTimestampInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new ICrossChainReceiver.ReceiverBridgeAdapterConfigInput[](0),
      new address[](0),
      new address[](0),
      new ICrossChainForwarder.ForwarderBridgeAdapterConfigInput[](0),
      new ICrossChainForwarder.BridgeAdapterToDisable[](0)
    );
  }

  function test_updateGuardian(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian,
    address newGuardian
  ) public createGGAC(defaultAdmin, retryGuardian, solveEmergencyGuardian) {
    _filterAddress(newGuardian);
    vm.startPrank(defaultAdmin);
    control.updateGuardian(newGuardian);
    assertEq(IWithGuardian(GovernanceV3Polygon.CROSS_CHAIN_CONTROLLER).guardian(), newGuardian);
    vm.stopPrank();
  }

  function test_updateGuardianWhenWrongCaller(
    address defaultAdmin,
    address retryGuardian,
    address solveEmergencyGuardian,
    address newGuardian,
    address caller
  ) public createGGAC(defaultAdmin, retryGuardian, solveEmergencyGuardian) {
    vm.assume(caller != defaultAdmin);
    hoax(caller);
    vm.expectRevert(
      bytes(
        string.concat(
          'AccessControl: account 0x',
          TestUtils.toAsciiString(caller),
          ' is missing role 0x0000000000000000000000000000000000000000000000000000000000000000'
        )
      )
    );
    control.updateGuardian(newGuardian);
  }
}
