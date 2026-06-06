// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {DossierManifest} from "../src/libraries/DossierManifest.sol";

contract DossierManifestTest is Test {
    // --- Core functions ---

    function test_hasPrefix_matches() public pure {
        assertTrue(DossierManifest.hasPrefix("dossier://stats.x", "dossier://"));
    }

    function test_hasPrefix_noMatchOnDifferentPrefix() public pure {
        assertFalse(DossierManifest.hasPrefix("ipfs://stats.x", "dossier://"));
    }

    function test_hasPrefix_shorterValueIsFalse() public pure {
        assertFalse(DossierManifest.hasPrefix("doss", "dossier://"));
    }

    function test_hasPrefix_emptyPrefixAlwaysTrue() public pure {
        assertTrue(DossierManifest.hasPrefix("anything", ""));
    }

    function test_equals_byteIdentical() public pure {
        assertTrue(DossierManifest.equals("haaland", "haaland"));
    }

    function test_equals_differentStringsFalse() public pure {
        assertFalse(DossierManifest.equals("haaland", "mbappe"));
    }
}
