# OpenHarmony Runtime Tests

The supported test runner is Pester 5.6.1. Import that exact version before
running the suite so local and CI behavior stays consistent:

```powershell
Import-Module Pester -RequiredVersion 5.6.1 -Force
Invoke-Pester -Path eng/openharmony/tests -Output Detailed
```

Install the pinned version for the current user when it is not available:

```powershell
Install-Module Pester -RequiredVersion 5.6.1 -Scope CurrentUser -Force
```
