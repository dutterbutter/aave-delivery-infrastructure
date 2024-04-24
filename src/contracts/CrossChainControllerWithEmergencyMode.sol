// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {EmergencyConsumer} from './emergency/EmergencyConsumer.sol';
import {BaseCrossChainController} from './BaseCrossChainController.sol';
import {ICrossChainControllerWithEmergencyMode} from './interfaces/ICrossChainControllerWithEmergencyMode.sol';

/**
 * @title CrossChainControllerWithEmergencyMode
 * @author BGD Labs
 * @notice CrossChainController contract adopted for usage on the "L2" chains, connected with the Governance via bridge
 * @dev If an emergency is activated, solveEmergency method should be called with new configurations.
 */
contract CrossChainControllerWithEmergencyMode is
  ICrossChainControllerWithEmergencyMode,
  BaseCrossChainController,
  EmergencyConsumer
{
  constructor(address clEmergencyOracle) EmergencyConsumer(clEmergencyOracle) {}

  /// @inheritdoc ICrossChainControllerWithEmergencyMode
  function initialize(
    address owner,
    address guardian,
    address clEmergencyOracle,
    ConfirmationInput[] memory initialRequiredConfirmations,
    ReceiverBridgeAdapterConfigInput[] memory receiverBridgeAdaptersToAllow,
    ForwarderBridgeAdapterConfigInput[] memory forwarderBridgeAdaptersToEnable,
    address[] memory sendersToApprove
  ) external initializer {
    _updateCLEmergencyOracle(clEmergencyOracle);
    _baseInitialize(
      owner,
      guardian,
      initialRequiredConfirmations,
      receiverBridgeAdaptersToAllow,
      forwarderBridgeAdaptersToEnable,
      sendersToApprove
    );
  }

  /// @inheritdoc ICrossChainControllerWithEmergencyMode
  function solveEmergency(
    ConfirmationInput[] memory newConfirmations,
    ValidityTimestampInput[] memory newValidityTimestamp,
    ReceiverBridgeAdapterConfigInput[] memory receiverBridgeAdaptersToAllow,
    ReceiverBridgeAdapterConfigInput[] memory receiverBridgeAdaptersToDisallow,
    address[] memory sendersToApprove,
    address[] memory sendersToRemove,
    ForwarderBridgeAdapterConfigInput[] memory forwarderBridgeAdaptersToEnable,
    BridgeAdapterToDisable[] memory forwarderBridgeAdaptersToDisable
  )
    external
    // TODO: RequiredConfirmationsByReceiverChain[] memory requiredConfirmationsByReceiverChain does it make sense to also have req confirmations
    // on solve emergency? Even if when config for a destination network is set to 0, it implies that it will not be able to use adapters (as if
    // destination network was not "allowed" i dont really think that it implies that it is an emergency, as this would be able to be solved
    // by passing a new proposal. It does not affect receiving adapters configuration, so it does not break communication
    onlyGuardian
    onlyInEmergency
  {
    // receiver side
    _configureReceiverBasics(
      receiverBridgeAdaptersToAllow,
      receiverBridgeAdaptersToDisallow,
      newConfirmations
    );
    _updateMessagesValidityTimestamp(newValidityTimestamp);

    // forwarder side
    _configureForwarderBasics(
      forwarderBridgeAdaptersToEnable,
      forwarderBridgeAdaptersToDisable,
      sendersToApprove,
      sendersToRemove
    );
  }

  /// @notice method that ensures access control validation
  function _validateEmergencyAdmin() internal override onlyOwner {}
}
