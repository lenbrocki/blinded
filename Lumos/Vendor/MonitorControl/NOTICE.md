# Vendored from MonitorControl

`Arm64DDC.swift` is taken verbatim from the [MonitorControl](https://github.com/MonitorControl/MonitorControl)
project, which is licensed under the **MIT License**.

It implements Apple-Silicon DDC/CI brightness control: matching each `CGDirectDisplayID`
to its `IOAVService` via the IORegistry, and reading/writing VCP commands over I2C.

MIT License — Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others.

The private-framework symbols it relies on (`IOAVServiceCreateWithService`,
`IOAVServiceReadI2C`, `IOAVServiceWriteI2C`, `CoreDisplay_DisplayCreateInfoDictionary`) are
declared in `Lumos/Lumos-Bridging-Header.h`, also adapted from MonitorControl's bridging
header.
