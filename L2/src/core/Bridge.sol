// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import { IBridgeableToken } from "@ssv/src/core/interfaces/IBridgeableToken.sol";
import { IMailbox } from "@ssv/src/core/interfaces/IMailbox.sol";
import { IBridge } from "@ssv/src/core/interfaces/IBridge.sol";

/**
 * @title Bridge
 * @notice This contract handles token bridging between blockchain networks using a mailbox for cross-chain messages.
 *
 * @author
 * SSV Labs
 */
contract Bridge is IBridge {

    /// @notice The mailbox contract used for sending and receiving cross-chain messages.
    /// @dev This is set in the constructor and cannot be changed later.
    IMailbox public immutable mailbox;

    /// @notice Initializes the bridge with a mailbox address.
    /// @dev Sets the mailbox interface for all cross-chain operations.
    /// @param _mailbox The address of the mailbox contract.
    constructor(address _mailbox) {
        mailbox = IMailbox(_mailbox);
    }

    struct MsgHeader {
        uint256 sourceChain;
        address senderContract;
        uint256 destChain;
        address destContract;
        uint256 sessionId;
        string label;
    }

    struct FullMsg {
        MsgHeader header;
        bytes data;
    }

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
    ) external {
        if (msg.sender != sender) {
            revert Unauthorized();
        }

        IBridgeableToken(token).burn(sender, amount);

        bytes memory data = abi.encode(sender, receiver, token, amount);

        mailbox.write(otherChainId, destBridge, sessionId, "SEND", data);

        emit DataWritten(data);
    }

    /// @notice Aborts the sending of tokens from the current chain to another chain by returning amount tokens to the owner.
    /// @dev The message must have been save previously.
    /// @param otherChainId The ID of the destination blockchain.
    /// @param token The address of the token being transferred.
    /// @param sender The address sending the tokens (must be the caller).
    /// @param receiver The address that will receive the tokens on the destination chain.
    /// @param amount The number of tokens to transfer.
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
    ) external {
        if (msg.sender != sender) {
            revert Unauthorized();
        }

        bytes memory data = abi.encode(sender, receiver, token, amount);

        mailbox.unwrite(otherChainId, destBridge, sessionId, "SEND", data);

        IBridgeableToken(token).mint(sender, amount);

        emit DataUnwritten(data);
    }

    // TODO: Check if there is a problem in delivering the tokens right away, when burning them back if cancel occurs.
    /// @notice Receives and processes tokens on the destination chain by minting them after reading the source message and saving them to be delivered afterwards.
    /// @dev The caller must be the receiver. It checks the message, verifies sender and receiver, mints tokens, and sends an acknowledgment back.
    /// @param otherChainId The ID of the source blockchain.
    /// @param sender The address that sent the tokens from the source chain.
    /// @param receiver The address receiving the tokens (must be the caller).
    /// @param sessionId The unique ID for this transaction session.
    /// @param srcBridge The address of the Bridge contract on the source chain.
    function recv(
        uint256 otherChainId,
        address sender,
        address receiver,
        uint256 sessionId,
        address srcBridge
    ) external returns (address token, uint256 amount){
        if (msg.sender != receiver) {
            revert Unauthorized();
        }

        bytes memory message = mailbox.read(
            otherChainId,
            srcBridge,
            sessionId,
            "SEND"
        );

        if (message.length == 0) {
            revert EmptySourceChainMessage();
        }

        address readSender;
        address readReceiver;

        (readSender, readReceiver, token, amount) = abi.decode(
            message,
            (address, address, address, uint256)
        );

        if (readSender != sender) {
            revert SenderMismatch();
        }
        if (readReceiver != receiver) {
            revert ReceiverMismatch();
        }

        IBridgeableToken(token).mint(receiver, amount);

        message = abi.encode("OK");
        mailbox.write(otherChainId, srcBridge, sessionId, "ACK SEND", message);

        emit TokensReceived(token, amount);

        return (token, amount);
    }

    /// @notice Aborts the receiving of tokens by burning the deposited tokens
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
    ) external {
        if (msg.sender != receiver) {
            revert Unauthorized();
        }

        bytes memory message = mailbox.read(
            otherChainId,
            srcBridge,
            sessionId,
            "SEND"
        );

        if (message.length == 0) {
            revert EmptySourceChainMessage();
        }

        address readSender;
        address readReceiver;
        address token;
        uint256 amount;

        (readSender, readReceiver, token, amount) = abi.decode(
            message,
            (address, address, address, uint256)
        );

        if (readSender != sender) {
            revert SenderMismatch();
        }
        if (readReceiver != receiver) {
            revert ReceiverMismatch();
        }

        message = abi.encode("OK");
        mailbox.unwrite(otherChainId, srcBridge, sessionId, "ACK SEND", message);

        IBridgeableToken(token).burn(receiver, amount);

        emit TokensReturned(token, amount);
    }

    /// @notice Checks for an acknowledgment message from the destination chain.
    /// @dev This is a view function to read the ACK.
    /// @param chainDest The ID of the destination blockchain.
    /// @param destBridge The address of the Bridge contract on the destination chain.
    /// @param sessionId The unique ID for the transaction session.
    /// @return The acknowledgment message as bytes, or empty if none exists.
    function checkAck(
        uint256 chainDest,
        address destBridge,
        uint256 sessionId
    ) external view returns (bytes memory) {
        return mailbox.read(chainDest, destBridge, sessionId, "ACK SEND");
    }
}
