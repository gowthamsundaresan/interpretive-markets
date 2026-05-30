// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ResolutionTypes} from "../libraries/ResolutionTypes.sol";

/// @title IMarket Interface
/// @notice Singleton registry of interpretive markets and their verdicts. Each market pins a
///         framework, data source, model, and prompt template at creation; resolution is gated
///         by a signed verdict from a judge registered in the JudgeRegistry. v0 stub: no trading.
interface IMarket {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Parameters for creating a new market
    /// @param question Human-readable question text
    /// @param frameworkId Registered framework id (sha256 of tarball) used to evaluate
    /// @param dataSourceSpec Opaque blob describing how the judge fetches evidence
    /// @param modelId EigenAI model id pinned for inference (e.g. keccak256("gpt-oss-120b"))
    /// @param promptTemplateHash Hash of the deterministic prompt template
    /// @param resolutionTime Earliest timestamp at which the market may be resolved
    /// @param judgeImageDigest The judge image digest authorized to resolve this market
    struct MarketInit {
        string question;
        bytes32 frameworkId;
        bytes dataSourceSpec;
        bytes32 modelId;
        bytes32 promptTemplateHash;
        uint64 resolutionTime;
        bytes32 judgeImageDigest;
    }

    /// @notice Stored record for a market
    /// @param init Immutable market parameters set at creation
    /// @param creator Address that created the market
    /// @param createdAt Block timestamp at creation
    /// @param verdict Verdict struct populated by the judge on resolution (zero-valued until then)
    /// @param bundleRef Pointer to the re-execution bundle on EigenDA/IPFS
    /// @param resolvedAt Block timestamp at resolution (zero until then)
    /// @param disputed Whether a watcher has filed a dispute against this market's verdict
    struct Market {
        MarketInit init;
        address creator;
        uint64 createdAt;
        ResolutionTypes.Verdict verdict;
        string bundleRef;
        uint64 resolvedAt;
        bool disputed;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @notice Emitted when a market is created
    /// @param marketId Unique identifier for the market
    /// @param frameworkId Framework id used to evaluate
    /// @param judgeImageDigest Judge image digest authorized to resolve
    /// @param creator Address that created the market
    event MarketCreated(
        uint256 indexed marketId,
        bytes32 indexed frameworkId,
        bytes32 indexed judgeImageDigest,
        address creator
    );

    /// @notice Emitted when a verdict is posted for a market
    /// @param marketId The market id
    /// @param signer The judge signer that produced the verdict
    /// @param bundleRef Pointer to the re-execution bundle
    event VerdictPosted(uint256 indexed marketId, address indexed signer, string bundleRef);

    /// @notice Emitted when a watcher files a dispute against a market's verdict
    /// @param marketId The market id
    /// @param disputer The address that filed the dispute
    /// @param evidence Opaque evidence blob (e.g. counter-execution hash)
    event VerdictDisputed(uint256 indexed marketId, address indexed disputer, bytes evidence);

    // ============================================================================
    // ERRORS
    // ============================================================================

    /// @notice Reverts when an unknown framework id is referenced at market creation
    /// @param frameworkId The unregistered framework id
    error UnknownFramework(bytes32 frameworkId);

    /// @notice Reverts when an unknown judge image is referenced at market creation
    /// @param imageDigest The unregistered judge image digest
    error UnknownJudge(bytes32 imageDigest);

    /// @notice Reverts when resolutionTime is not in the future at creation
    error InvalidResolutionTime();

    /// @notice Reverts when interacting with a non-existent market
    /// @param marketId The unknown market id
    error UnknownMarket(uint256 marketId);

    /// @notice Reverts when resolution is attempted before resolutionTime
    /// @param marketId The market id
    /// @param resolutionTime The earliest allowed resolution timestamp
    error TooEarly(uint256 marketId, uint64 resolutionTime);

    /// @notice Reverts when resolution is attempted on an already-resolved market
    /// @param marketId The market id
    error AlreadyResolved(uint256 marketId);

    /// @notice Reverts when the verdict signature recovers to an unauthorized signer
    /// @param recovered The signer recovered from the signature
    error UnauthorizedSigner(address recovered);

    /// @notice Reverts when a dispute is filed against an unresolved market
    /// @param marketId The market id
    error NotResolved(uint256 marketId);

    /// @notice Reverts when a dispute is filed twice for the same market
    /// @param marketId The market id
    error AlreadyDisputed(uint256 marketId);

    // ============================================================================
    // FUNCTIONS
    // ============================================================================

    /// @notice Create a new market with immutable parameters
    /// @param params The market creation parameters
    /// @return marketId The id assigned to the new market
    function createMarket(MarketInit calldata params) external returns (uint256 marketId);

    /// @notice Post a signed verdict for a market. Signature must recover to the authorized
    ///         signer for the market's judge image digest.
    /// @param marketId The market id
    /// @param verdict The verdict struct
    /// @param bundleRef Pointer to the re-execution bundle (EigenDA BlobKey or ipfs://<cid>)
    /// @param signature ECDSA signature over keccak256(abi.encode(marketId, verdict, bundleRef))
    function resolve(
        uint256 marketId,
        ResolutionTypes.Verdict calldata verdict,
        string calldata bundleRef,
        bytes calldata signature
    ) external;

    /// @notice File a dispute against a resolved market's verdict. v0 only emits an event and
    ///         flips the disputed flag; slashing/arbitration is deferred to v1.
    /// @param marketId The market id
    /// @param evidence Opaque evidence blob (e.g. counter-execution hash)
    function disputeVerdict(uint256 marketId, bytes calldata evidence) external;

    /// @notice Fetch the full market record for a given id
    /// @param marketId The market id
    /// @return market The stored market record
    function get(uint256 marketId) external view returns (Market memory market);

    /// @notice The next market id that will be assigned by createMarket
    /// @return nextId The next market id
    function nextMarketId() external view returns (uint256 nextId);
}
