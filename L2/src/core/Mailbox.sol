// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import { IMailbox } from "@ssv/src/core/interfaces/IMailbox.sol";
import { console } from "forge-std/console.sol";

/**
 * @title Mailbox
 * @notice The Mailbox Contract to manage chain interaction via CIRC/Espresso.
 * @dev It stores messages in inboxes and outboxes using unique keys. Roots are updated for each chain to track changes. Only the coordinator can add to the inbox for security.
 *
 * @author
 * SSV Labs
 */
contract Mailbox is IMailbox {

    /// @notice The address of the coordinator that can add messages to the inbox.
    /// @dev This is set once in the constructor and can't be changed.
    address public immutable COORDINATOR;

    /// @notice List of chain IDs that have messages in the inbox.
    uint256[] public chainIDsInbox;

    /// @notice List of chain IDs that have messages in the outbox.
    uint256[] public chainIDsOutbox;

    /// @notice Single address allowed to call root-update helpers (typically the local Bridge contract).
    /// @dev Set once by the coordinator. This prevents arbitrary callers (EOAs or other contracts)
    ///      from toggling inbox/outbox roots while allowing the Bridge contract to call these helpers.
    address public allowedUpdater;

    /// @notice Emitted when the allowed updater address is set.
    event UpdaterSet(address indexed updater);

    /// @notice Mapping from chain ID to the root hash of its inbox.
    /// @dev The root is updated each time a new message is added to the inbox for that chain.
    mapping(uint256 chainId => bytes32 inboxRoot) public inboxRootPerChain;

    /// @notice Mapping from chain ID to the root hash of its outbox.
    /// @dev The root is updated each time a new message is added to the outbox for that chain.
    mapping(uint256 chainId => bytes32 outboxRoot) public outboxRootPerChain;

    /// @notice Mapping from message key to the message data in the inbox.
    mapping(bytes32 key => bytes message) public inbox;

    /// @notice Mapping from message key to the message data in the outbox.
    mapping(bytes32 key => bytes message) public outbox;

    /// @notice Mapping to track if a key has been created (used in inbox or outbox).
    mapping(bytes32 key => bool used) public createdKeys;

    /// @notice List of headers for messages in the inbox.
    MessageHeader[] public messageHeaderListInbox;

    /// @notice List of headers for messages in the outbox.
    MessageHeader[] public messageHeaderListOutbox;

    /// @notice Modifier to restrict access to only the coordinator.
    /// @dev Reverts if the caller is not the coordinator.
    modifier onlyCoordinator() {
        if (msg.sender != COORDINATOR) revert InvalidCoordinator();
        _;
    }

    /// @notice Restricts calls to the configured updater (the Bridge contract for this chain).
    modifier onlyAllowedUpdater() {
        if (msg.sender != allowedUpdater) revert InvalidAllowedUpdater();
        _;
    }

    /// @notice Sets up the mailbox with the coordinator's address.
    /// @dev The coordinator is the only one who can add incoming messages.
    /// @param _coordinator The address of the trusted coordinator.
    constructor(address _coordinator) {
        COORDINATOR = _coordinator;
    }

    /// @notice Set the single allowed updater address (callable only by the coordinator).
    /// @dev Can only be set once. Coordinator should set this to the Bridge contract address
    ///      that will call `updateInboxRoot` / `updateOutboxRoot` on this mailbox.
    /// @param _updater The address of the contract allowed to call root-update helpers.
    function setAllowedUpdater(address _updater) external onlyCoordinator {
        if (allowedUpdater != address(0)) revert AllowedUpdaterAlreadySet();
        allowedUpdater = _updater;
        emit UpdaterSet(_updater);
    }

    /// @notice Creates and returns a unique key for a message based on its details.
    /// @dev This key is a hash of all the message parts, used to store and find messages.
    /// @param chainMessageSender The ID of the chain sending the message.
    /// @param chainMessageRecipient The ID of the chain receiving the message.
    /// @param sender The address sending the message.
    /// @param receiver The address receiving the message.
    /// @param sessionId A unique number for the session.
    /// @param label A tag to tell different actions apart in the same session.
    /// @return key The unique hash key for the message.
    function getKey(
        uint256 chainMessageSender,
        uint256 chainMessageRecipient,
        address sender,
        address receiver,
        uint256 sessionId,
        bytes calldata label
    ) public pure returns (bytes32 key) {
        key = keccak256(
            abi.encodePacked(
                chainMessageSender,
                chainMessageRecipient,
                sender,
                receiver,
                sessionId,
                label
            )
        );
    }

    /// @notice Reads a message from the inbox.
    /// @dev Anyone can read messages. Function checks if the message exists and throws if it does not.
    /// @param chainMessageSender The ID of the chain that sent the message.
    /// @param sender The address that sent the message.
    /// @param sessionId The session number.
    /// @param label The tag for the action.
    /// @return message The data of the message.
    function read(
        uint256 chainMessageSender,
        address sender,
        uint256 sessionId,
        bytes calldata label
    ) external view returns (bytes memory message) {
        bytes32 key = getKey(
            chainMessageSender,
            block.chainid,
            sender,
            msg.sender,
            sessionId,
            label
        );

        if (inbox[key].length == 0 && !createdKeys[key]) {
            revert MessageNotFound();
        }

        return inbox[key];
    }

    /// @notice Marks a message from the inbox as consumed.
    /// @dev This function sets a message to a consumed state to ensure that recv cannot be done twice
    /// @param chainMessageSender The ID of the chain that sent the message.
    /// @param sender The address that sent the message.
    /// @param sessionId The session number.
    /// @param label The tag for the action.
    function markConsumed(
        uint256 chainMessageSender,
        address sender,
        uint256 sessionId,
        bytes calldata label
    ) external onlyAllowedUpdater{
        // add access control here (e.g., only receiver or only coordinator)
        bytes32 key = getKey(
            chainMessageSender,
            block.chainid,
            sender,
            msg.sender,
            sessionId,
            label
        );
        (bytes memory data, bool consumed) = abi.decode(inbox[key], (bytes, bool));
        if (!consumed) {
            inbox[key] = abi.encode(data, true);
        }
    }


    /// @notice Writes a message to the outbox to send to another chain.
    /// @dev Any contract can write to the outbox. It creates a key, stores the data, and updates the outbox root.
    /// @param chainDestId The ID of the chain receiving the message.
    /// @param receiver The bridge address that will receive the message.
    /// @param sessionId The session number.
    /// @param label The tag for the action.
    /// @param data The message data to send.
    function write(
        uint256 chainDestId,
        address receiver,
        uint256 sessionId,
        bytes calldata label,
        bytes calldata data
    ) external onlyAllowedUpdater{
        bytes32 key = getKey(
            block.chainid,
            chainDestId,
            msg.sender,
            receiver,
            sessionId,
            label
        );
        outbox[key] = data;
        createdKeys[key] = true;
        messageHeaderListOutbox.push(
            MessageHeader(
                block.chainid,
                chainDestId,
                msg.sender,
                receiver,
                sessionId,
                label
            )
        );

        emit NewOutboxKey(messageHeaderListOutbox.length - 1, key);
    }

    /// @notice Removes a previously written message from the outbox.
    /// @dev Executed by the coordinator. Marks the key as unused, removes the data and updates the outbox root.
    /// @param chainDestId The ID of the chain receiving the message.
    /// @param receiver The address that will receive the message.
    /// @param sessionId The session number.
    /// @param label The tag for the action.
    /// @param data The message data to send.
    function unwrite(
        uint256 chainDestId,
        address receiver,
        uint256 sessionId,
        bytes calldata label,
        bytes calldata data
    ) external onlyAllowedUpdater{
        bytes32 key = getKey(
            block.chainid,
            chainDestId,
            msg.sender,
            receiver,
            sessionId,
            label
        );

        if (outbox[key].length == 0 && !createdKeys[key] && keccak256(abi.encodePacked(outbox[key])) != keccak256(abi.encodePacked(data))) {
            revert MessageNotFound();
        }

        delete outbox[key];
        createdKeys[key] = false;

        // TODO: Does not maintain order, making this loop a performance issue.
        for(uint i = 0; i < messageHeaderListOutbox.length; i++) {
            if(_headerEquals(messageHeaderListOutbox[i],
                block.chainid,
                chainDestId,
                msg.sender,
                receiver,
                sessionId,
                label
            )) {
                messageHeaderListOutbox[i] = messageHeaderListOutbox[messageHeaderListOutbox.length - 1];
                messageHeaderListOutbox.pop();
                break;
            }
        }

        emit DeletedOutboxMessage( key);
    }

    /// @notice Adds a message to the inbox. Only the coordinator can do this.
    /// @dev This is for incoming messages from other chains. It updates the inbox root.
    /// @param chainSenderId The ID of the chain that sent the message.
    /// @param sender The address that sent it.
    /// @param receiver The address receiving it.
    /// @param sessionId The session number.
    /// @param label The tag for the action.
    /// @param data The message data.
    function putInbox(
        uint256 chainSenderId,
        address sender,
        address receiver,
        uint256 sessionId,
        bytes calldata label,
        bytes calldata data
    ) external onlyCoordinator {
        bytes32 key = getKey(
            chainSenderId,
            block.chainid,
            sender,
            receiver,
            sessionId,
            label
        );

        inbox[key] = abi.encode(data, false);
        createdKeys[key] = true;
        messageHeaderListInbox.push(
            MessageHeader(chainSenderId, block.chainid, sender, receiver, sessionId, label)
        );

        emit NewInboxKey(messageHeaderListInbox.length - 1, key);
    }

    /// @notice Removes a message to the inbox. Only the coordinator can do this.
    /// @dev This is for incoming messages from other chains. It updates the inbox root.
    /// @param chainSenderId The ID of the chain that sent the message.
    /// @param sender The address that sent it.
    /// @param receiver The address receiving it.
    /// @param sessionId The session number.
    /// @param label The tag for the action.
    /// @param data The message data.
    function removeInbox(
        uint256 chainSenderId,
        address sender,
        address receiver,
        uint256 sessionId,
        bytes calldata label,
        bytes calldata data
    ) external onlyCoordinator{
        bytes32 key = getKey(
            chainSenderId,
            block.chainid,
            sender,
            receiver,
            sessionId,
            label
        );

        if (
            inbox[key].length == 0 &&
            !createdKeys[key] &&
            keccak256(abi.encodePacked(inbox[key])) != keccak256(abi.encodePacked(data))) {
            revert MessageNotFound();
        }

        delete inbox[key];
        createdKeys[key] = false;

        // TODO: Does not maintain order, making this loop a performance issue.
        for(uint i = 0; i < messageHeaderListInbox.length; i++) {
            if(_headerEquals(messageHeaderListInbox[i],
                chainSenderId,
                block.chainid,
                sender,
                receiver,
                sessionId,
                label
            )) {
                messageHeaderListInbox[i] = messageHeaderListInbox[messageHeaderListInbox.length - 1];
                messageHeaderListInbox.pop();
                break;
            }
        }

        emit DeletedInboxMessage(key);
    }

    /**
    * @notice Update the inbox root for a source chain entry.
    * @param chainMessageSender Source chain id that originally emitted the message.
    * @param sender Originating address on the source chain.
    * @param sessionId Session identifier for the message/flow.
    * @param label Opaque label/tag distinguishing the message type.
    */
    function updateInboxRoot(
        uint256 chainMessageSender,
        address sender,
        uint256 sessionId,
        bytes calldata label
    ) external onlyAllowedUpdater {
        bytes32 key = getKey(
            chainMessageSender,
            block.chainid,
            sender,
            msg.sender,
            sessionId,
            label
        );

        if(!createdKeys[key]){
            revert MessageNotFound();
        }

        (bytes memory data,) = abi.decode(
            inbox[key],
            (bytes,bool)
        );

        if (inboxRootPerChain[chainMessageSender] == bytes32(0)) {
            chainIDsInbox.push(chainMessageSender);
        }

        inboxRootPerChain[chainMessageSender] ^= keccak256(
            abi.encode(key, data)
        );
    }

    /**
    * @notice Update the per-destination-chain outbox root for a single outbox entry.
    * @dev This updates `outboxRootPerChain[chainMessageRecipient]` by XORing it with
    *      keccak256(abi.encode(key, data)). If the previous root was the zero value,
    *      the destination chain id is appended to `chainIDsOutbox`.
    * @param chainMessageRecipient The destination chain ID whose outbox root is being updated.
    * @param receiver The remote receiver address on `chainMessageRecipient`.
    * @param sessionId Session identifier associated with the message.
    * @param label Opaque label/tag that distinguishes the message type.
    */
    function updateOutboxRoot(
        uint256 chainMessageRecipient,
        address receiver,
        uint256 sessionId,
        bytes calldata label
    ) external onlyAllowedUpdater {
        bytes32 key = getKey(
            block.chainid,
            chainMessageRecipient,
            msg.sender,
            receiver,
            sessionId,
            label
        );

        if(!createdKeys[key]){
            revert MessageNotFound();
        }

        if (outboxRootPerChain[chainMessageRecipient] == bytes32(0)) {
            chainIDsOutbox.push(chainMessageRecipient);
        }

        outboxRootPerChain[chainMessageRecipient] ^= keccak256(
            abi.encode(key, outbox[key])
        );
    }

    /// @dev Helper to compare a storage MessageHeader with provided fields.
    function _headerEquals(
        MessageHeader storage h,
        uint256 chainSrc,
        uint256 chainDest,
        address sender,
        address receiver,
        uint256 sessionId,
        bytes calldata label
    ) internal view returns (bool) {
        // compare non-bytes fields directly and bytes via keccak256
        if (h.chainSrc != chainSrc) return false;
        if (h.chainDest != chainDest) return false;
        if (h.sender != sender) return false;
        if (h.receiver != receiver) return false;
        if (h.sessionId != sessionId) return false;
        if (keccak256(abi.encodePacked(h.label)) != keccak256(abi.encodePacked(label))) return false;
        return true;
    }

    /// @notice Computes the key for a message in the inbox using its ID.
    /// @dev Useful for checking or verifying keys from the header list.
    /// @param id The index in the inbox header list.
    /// @return The computed key hash.
    function computeKey(uint256 id) external view returns (bytes32) {
        if (id >= messageHeaderListInbox.length) {
            revert InvalidId();
        }

        MessageHeader storage m = messageHeaderListInbox[id];

        return keccak256(
                abi.encodePacked(
                    m.chainSrc,
                    m.chainDest,
                    m.sender,
                    m.receiver,
                    m.sessionId,
                    m.label
                )
            );
    }
}