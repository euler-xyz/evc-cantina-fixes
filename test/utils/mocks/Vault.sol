// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Target.sol";
import "src/interfaces/ICreditVault.sol";
import "src/interfaces/ICreditVaultProtocol.sol";
import "src/CreditVaultProtocol.sol";

// mock vault contract that implements required interface and helps with status checks verification
contract Vault is ICreditVault, Target {
    ICVP public immutable cvp;

    uint internal vaultStatusState;
    uint internal accountStatusState;

    bool[] internal vaultStatusChecked;
    address[] internal accountStatusChecked;

    constructor(ICVP _cvp) {
        cvp = _cvp;
    }

    function reset() external {
        vaultStatusState = 0;
        accountStatusState = 0;
        delete vaultStatusChecked;
        delete accountStatusChecked;
    }

    function clearChecks() external {
        delete vaultStatusChecked;
        delete accountStatusChecked;
    }

    function setVaultStatusState(uint state) external {
        vaultStatusState = state;
    }

    function setAccountStatusState(uint state) external {
        accountStatusState = state;
    }

    function pushVaultStatusChecked() external {
        vaultStatusChecked.push(true);
    }

    function pushAccountStatusChecked(address account) external {
        accountStatusChecked.push(account);
    }

    function getVaultStatusChecked() external view returns (bool[] memory) {
        return vaultStatusChecked;
    }

    function getAccountStatusChecked()
        external
        view
        returns (address[] memory)
    {
        return accountStatusChecked;
    }

    function disableController(address account) external virtual override {
        cvp.disableController(account);
    }

    function checkVaultStatus()
        external
        virtual
        override
        returns (bool isValid, bytes memory data)
    {
        if (vaultStatusState == 0) return (true, "");
        else if (vaultStatusState == 1)
            return (false, "vault status violation");
        else revert("invalid vault");
    }

    function checkAccountStatus(
        address,
        address[] memory
    ) external view virtual override returns (bool isValid, bytes memory data) {
        if (accountStatusState == 0) return (true, "");
        else if (accountStatusState == 1)
            return (false, "account status violation");
        else revert("invalid account");
    }

    function requireChecks(address account) external payable {
        cvp.requireAccountStatusCheck(account);
        cvp.requireVaultStatusCheck();
    }

    function call(address target, bytes memory data) external payable {
        (bool success, ) = target.call{value: msg.value}(data);
        require(success, "call/failed");
    }
}

contract VaultMaliciousBatch is Vault {
    constructor(ICVP _cvp) Vault(_cvp) {}

    function disableController(address account) external override {}

    function checkVaultStatus()
        external
        virtual
        override
        returns (bool, bytes memory)
    {
        // try to reenter the CVP batch. if it were possible, one could defer other vaults status checks
        // by entering a batch here and making the checkStatusAll() malfunction. possible attack:
        // - execute a batch with any item that calls checkVaultStatus() on vault A
        // - checkStatusAll() calls checkVaultStatus() on vault A
        // - vault A reenters a batch with any item that calls checkVaultStatus() on vault B
        // - because checks are deferred, checkVaultStatus() on vault B is not executed the right away
        // - control is handed over back to checkStatusAll() which had numElements = 1 when entering the loop
        // - the loop ends and "delete vaultStatusChecks" is called removing the vault status check scheduled on vault B
        ICVP.BatchItem[] memory items = new ICVP.BatchItem[](1);
        items[0].allowError = false;
        items[0].onBehalfOfAccount = address(0);
        items[0].targetContract = address(0);
        items[0].msgValue = 0;
        items[0].data = "";

        try cvp.batch(items) {
            assert(false);
        } catch (bytes memory err) {
            assert(
                bytes4(err) == CreditVaultProtocol.CVP_ChecksReentrancy.selector
            );
            return (false, "malicious vault batch");
        }

        return (true, "");
    }

    function checkAccountStatus(
        address,
        address[] memory
    ) external pure override returns (bool isValid, bytes memory data) {
        return (true, "");
    }
}

// same as VaultMaliciousBatch but calls batchRevert() instead of batch() for coverage
contract VaultMaliciousBatchRevert is VaultMaliciousBatch {
    constructor(ICVP _cvp) VaultMaliciousBatch(_cvp) {}

    function checkVaultStatus() external override returns (bool, bytes memory) {
        // try to reenter the CVP batch. if it were possible, one could defer other vaults status checks
        // by entering a batch here and making the checkStatusAll() malfunction. possible attack:
        // - execute a batch with any item that calls checkVaultStatus() on vault A
        // - checkStatusAll() calls checkVaultStatus() on vault A
        // - vault A reenters a batch with any item that calls checkVaultStatus() on vault B
        // - because checks are deferred, checkVaultStatus() on vault B is not executed the right away
        // - control is handed over back to checkStatusAll() which had numElements = 1 when entering the loop
        // - the loop ends and "delete vaultStatusChecks" is called removing the vault status check scheduled on vault B
        ICVP.BatchItem[] memory items = new ICVP.BatchItem[](1);
        items[0].allowError = false;
        items[0].onBehalfOfAccount = address(0);
        items[0].targetContract = address(0);
        items[0].msgValue = 0;
        items[0].data = "";

        try cvp.batchRevert(items) {
            assert(false);
        } catch (bytes memory err) {
            assert(
                bytes4(err) == CreditVaultProtocol.CVP_ChecksReentrancy.selector
            );
            return (false, "malicious vault batch revert");
        }

        return (true, "");
    }
}