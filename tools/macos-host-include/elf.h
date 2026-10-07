#ifndef U5A_HOST_ELF_H
#define U5A_HOST_ELF_H
#include <libelf/sys_elf.h>

#ifndef R_386_32
#define R_386_32 1
#endif
#ifndef R_386_PC32
#define R_386_PC32 2
#endif

#ifndef STT_SPARC_REGISTER
#define STT_SPARC_REGISTER 13
#endif

#ifndef R_ARM_PC24
#define R_ARM_PC24 1
#endif
#ifndef R_ARM_ABS32
#define R_ARM_ABS32 2
#endif
#ifndef R_ARM_REL32
#define R_ARM_REL32 3
#endif
#ifndef R_ARM_THM_PC22
#define R_ARM_THM_PC22 10
#endif
#ifndef R_ARM_CALL
#define R_ARM_CALL 28
#endif
#ifndef R_ARM_JUMP24
#define R_ARM_JUMP24 29
#endif
#ifndef R_ARM_THM_JUMP24
#define R_ARM_THM_JUMP24 30
#endif
#ifndef R_ARM_MOVW_ABS_NC
#define R_ARM_MOVW_ABS_NC 43
#endif
#ifndef R_ARM_MOVT_ABS
#define R_ARM_MOVT_ABS 44
#endif
#ifndef R_ARM_THM_MOVW_ABS_NC
#define R_ARM_THM_MOVW_ABS_NC 47
#endif
#ifndef R_ARM_THM_MOVT_ABS
#define R_ARM_THM_MOVT_ABS 48
#endif
#ifndef R_ARM_THM_JUMP19
#define R_ARM_THM_JUMP19 51
#endif

#ifndef R_MIPS_32
#define R_MIPS_32 2
#endif
#ifndef R_MIPS_26
#define R_MIPS_26 4
#endif
#ifndef R_MIPS_HI16
#define R_MIPS_HI16 5
#endif
#ifndef R_MIPS_LO16
#define R_MIPS_LO16 6
#endif

#endif
