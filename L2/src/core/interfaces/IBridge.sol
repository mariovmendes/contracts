// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title IBridge Interface
 * @notice Defines the structure for a bridge contract that transfers tokens between chains.
 *
 * @author
 * SSV Labs
 */
interface IBridge {

    /// @notice Error thrown when the caller is not authorized (not the sender or receiver).
    error Unauthorized();

    /// @notice Error when the caller is not the coordinator.
    error InvalidCoordinator();

    /// @notice Error thrown when there is no message from the source chain.
    error EmptySourceChainMessage();

    /// @notice Error when trying to read a message that has already been consumed.
    error MessageAlreadyConsumed();

    /// @notice Errow when confirming/aborting a transaction with a message that has not been processed
    error MessageNotConsumed();

    /// @notice Error thrown when the sender in the message does not match the expected sender.
    error SenderMismatch();

    /// @notice Error thrown when the receiver in the message does not match the expected receiver.
    error ReceiverMismatch();

    /// @notice Emitted when data is written to the mailbox for cross-chain transfer.
    /// @param data The encoded data sent in the message.
    event DataWritten(bytes data);

    /// @notice Emitted when tokens are successfully received and minted on the destination chain.
    /// @param token The address of the token received.
    /// @param amount The amount of tokens received.
    event TokensReceived(address token, uint256 amount);

    /// @notice Emitted when tokens are burned on the destination chain to be returned to origin chain.
    /// @param token The address of the token.
    /// @param amount The amount of tokens burned.
    event TokensReturned(address token, uint256 amount);

    /// @notice Emitted when tokens are sent to the destination chain's address.
    /// @param token The address of the token.
    /// @param amount The amount of tokens delivered.
    event TokensDelivered(address token, uint256 amount);

    /// @notice Prepares the sending of tokens from the current chain to another chain by burning them and sending a message.
    /// @dev The caller must be the tokens sender. Tokens are burned, and a message is emitted for the destination bridge to process.
    /// @param otherChainId The ID of the destination blockchain.
    /// @param token The address of the token being transferred.
    /// @param sender The address sending the tokens (must be the caller).
    /// @param receiver The address that will receive the tokens on the destination chain.
    /// @param amount The number of tokens to transfer.
    /// @param sessionId A unique ID for this transaction session.
    /// @param destBridge The address of the Bridge contract on the destination chain.
    function send(
        uint256 otherChainId,
        address token,
        address sender,
        address receiver,
        uint256 amount,
        uint256 sessionId,
        address destBridge
    ) external;

    /// @notice Confirms that the tokens were sent by consuming the ack message received from the destBridge
    /// @dev The ack message is consumed, and an event is transmitted to the network
    /// @param otherChainId The ID of the destination blockchain.
    /// @param token The address of the token being transferred.
    /// @param sender The address sending the tokens (must be the caller).
    /// @param receiver The address that will receive the tokens on the destination chain.
    /// @param amount The number of tokens to transfer.
    /// @param sessionId A unique ID for this transaction session.
    /// @param destBridge The address of the Bridge contract on the destination chain.
    function sendConfirm(
        uint256 otherChainId,
        address token,
        address sender,
        address receiver,
        uint256 amount,
        uint256 sessionId,
        address destBridge
    ) external;

    /// @notice Aborts the sending of tokens from the current chain to another chain by returning amount tokens to the owner.
    /// @param otherChainId The ID of the destination blockchain.
    /// @param token The address of the token being transferred.
    /// @param sender The address sending the tokens (must be the caller).
    /// @param receiver The address that would receive the tokens on the destination chain.
    /// @param amount The number of tokens to cancel transferring.
    /// @param sessionId A unique ID for this transaction session.
    /// @param destBridge The address of the Bridge contract on the destination chain.
    function sendAbort(
        uint256 otherChainId,
        address token,
        address sender,
        address receiver,
        uint256 amount,
        uint256 sessionId,
        address destBridge
    ) external;


    /// @notice Function to receive tokens from another chain.
    /// @param chainSrc The ID of the source chain.
    /// @param sender The sender's address from the source chain.
    /// @param receiver The receiver's address.
    /// @param sessionId The session ID for tracking.
    /// @param srcBridge The bridge address on the source chain.
    function recv(
        uint256 chainSrc,
        address sender,
        address receiver,
        uint256 sessionId,
        address srcBridge
    ) external returns (address token, uint256 amount);

    /// @notice Confirms the receiving of tokens.
    /// @param otherChainId The ID of the source chain.
    /// @param sender The sender's address from the source chain.
    /// @param receiver The receiver's address.
    /// @param sessionId The session ID for tracking.
    /// @param srcBridge The bridge address on the source chain.
    function recvConfirm(
        uint256 otherChainId,
        address sender,
        address receiver,
        uint256 sessionId,
        address srcBridge
    ) external;

    /// @notice Aborts the receiving of tokens by burning the reserved tokens
    /// @dev The message must have been previously save.
    /// @param otherChainId The ID of the source blockchain.
    /// @param sender The address that sent the tokens from the source chain.
    /// @param receiver The address receiving the tokens (must be the caller).
    /// @param sessionId The unique ID for this transaction session.
    /// @param srcBridge The address of the Bridge contract on the source chain.
    function recvAbort(
        uint256 otherChainId,
        address sender,
        address receiver,
        uint256 sessionId,
        address srcBridge
    ) external;
}
