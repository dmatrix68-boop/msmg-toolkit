@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Interactive console tool: colored output via Write-Host is intended
        'PSAvoidUsingWriteHost',
        # Menu driven tool - confirmations are handled by Confirm-TkAction instead of ShouldProcess
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
