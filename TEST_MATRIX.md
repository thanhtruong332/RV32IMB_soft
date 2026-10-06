# Test matrix

All conditions execute the same pure-software AES-128 source. No hardware AES accelerator is instantiated or used.

| Case | Blocks | Testbench | Firmware image |
|---|---:|---|---|
| 16B_ECB | 1 | `sim/tb_expG_scale_rv32imb_16b_ecb.v` | `firmware/images/expG_16B_ECB.mem` |
| 256B_ECB | 16 | `sim/tb_expG_scale_rv32imb_256b_ecb.v` | `firmware/images/expG_256B_ECB.mem` |
| 4KiB_ECB | 256 | `sim/tb_expG_scale_rv32imb_4kib_ecb.v` | `firmware/images/expG_4KiB_ECB.mem` |
| 16B_CBC | 1 | `sim/tb_expG_scale_rv32imb_16b_cbc.v` | `firmware/images/expG_16B_CBC.mem` |
| 256B_CBC | 16 | `sim/tb_expG_scale_rv32imb_256b_cbc.v` | `firmware/images/expG_256B_CBC.mem` |
| 4KiB_CBC | 256 | `sim/tb_expG_scale_rv32imb_4kib_cbc.v` | `firmware/images/expG_4KiB_CBC.mem` |
| 16B_CFB-128 | 1 | `sim/tb_expG_scale_rv32imb_16b_cfb128.v` | `firmware/images/expG_16B_CFB128.mem` |
| 256B_CFB-128 | 16 | `sim/tb_expG_scale_rv32imb_256b_cfb128.v` | `firmware/images/expG_256B_CFB128.mem` |
| 4KiB_CFB-128 | 256 | `sim/tb_expG_scale_rv32imb_4kib_cfb128.v` | `firmware/images/expG_4KiB_CFB128.mem` |
| 16B_CTR | 1 | `sim/tb_expG_scale_rv32imb_16b_ctr.v` | `firmware/images/expG_16B_CTR.mem` |
| 256B_CTR | 16 | `sim/tb_expG_scale_rv32imb_256b_ctr.v` | `firmware/images/expG_256B_CTR.mem` |
| 4KiB_CTR | 256 | `sim/tb_expG_scale_rv32imb_4kib_ctr.v` | `firmware/images/expG_4KiB_CTR.mem` |
