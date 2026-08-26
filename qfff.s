.intel_syntax noprefix
# qfff - fetch minimalist in as without bloat

.section .bss
    .lcomm os_buf, 1024
    .lcomm pretty_buf, 128
    .lcomm utsname_buf, 390
    .lcomm sysinfo_buf, 128
    .lcomm uptime_str, 16
    .lcomm shell_buf, 64
    .lcomm wm_buf, 64
    .lcomm num_buf, 16

.section .rodata
logo1: .ascii "      _____       "
logo1_len = . - logo1
logo2: .ascii "    \\-     -/     "
logo2_len = . - logo2
logo3: .ascii " \\_/         \\    "
logo3_len = . - logo3
logo4: .ascii " |        O O |   "
logo4_len = . - logo4
logo5: .ascii " |_  <   )  3 )   "
logo5_len = . - logo5
logo6: .ascii " / \\         /"
logo6_len = . - logo6
logo7: .ascii "    /-_____-\\     "
logo7_len = . - logo7

lbl_os:     .ascii "os      "
lbl_kernel: .ascii "kernel  "
lbl_uptime: .ascii "uptime  "
lbl_shell:  .ascii "shell   "
lbl_wm:     .ascii "wm      "
lbl_len = 8

nl: .ascii "\n"

path_osrelease: .asciz "/etc/os-release"

key_pretty: .ascii "PRETTY_NAME=\""
key_pretty_len = . - key_pretty

key_shell: .ascii "SHELL="
key_shell_len = . - key_shell

key_xdg: .ascii "XDG_CURRENT_DESKTOP="
key_xdg_len = . - key_xdg

key_dsession: .ascii "DESKTOP_SESSION="
key_dsession_len = . - key_dsession

fallback_os: .asciz "Linux"
fallback_os_len = . - fallback_os - 1
fallback_wm: .asciz "unknown"
fallback_wm_len = . - fallback_wm - 1

suf_d: .ascii "d"
suf_h: .ascii "h"
suf_m: .ascii "m"

.section .text
.global _start

# ---------------- helpers ----------------

# write_n: rdi=ptr, rsi=len  -> writes to stdout
write_n:
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, 1
    mov rax, 1
    syscall
    ret

# strlen: rdi=ptr -> rax=len (null terminated)
strlen:
    xor rax, rax
1:
    cmp byte ptr [rdi+rax], 0
    je 2f
    inc rax
    jmp 1b
2:
    ret

# print_cstr: rdi=ptr (null terminated) -> writes to stdout
print_cstr:
    push rdi
    call strlen
    pop rsi
    mov rdx, rax
    mov rdi, 1
    mov rax, 1
    syscall
    ret

# find_substr: rdi=haystack, rsi=haystack_len, rdx=needle, rcx=needle_len
# -> rax = pointer to match, or 0 if not found
find_substr:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi          # haystack
    mov r13, rsi          # haystack_len
    mov r14, rdx          # needle
    mov r15, rcx          # needle_len
    xor rbx, rbx          # i = 0
3:
    mov rax, r13
    sub rax, rbx
    cmp rax, r15
    jl 6f                  # not enough bytes left
    xor rcx, rcx           # j = 0
4:
    cmp rcx, r15
    je 7f                  # full match
    lea r8, [r12+rbx]
    mov al, [r8+rcx]
    cmp al, [r14+rcx]
    jne 5f
    inc rcx
    jmp 4b
5:
    inc rbx
    jmp 3b
6:
    xor rax, rax
    jmp 8f
7:
    lea rax, [r12+rbx]
8:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# str_ncmp_prefix: rdi=str, rsi=prefix, rdx=prefix_len -> rax=1 if match else 0
str_ncmp_prefix:
    xor rcx, rcx
1:
    cmp rcx, rdx
    je 3f
    mov al, [rdi+rcx]
    cmp al, [rsi+rcx]
    jne 2f
    inc rcx
    jmp 1b
2:
    xor rax, rax
    ret
3:
    mov rax, 1
    ret

# itoa_unsigned: rdi=value, rsi=out buf -> rax=length written (no null term)
itoa_unsigned:
    push rbx
    push r12
    push r13
    mov r12, rsi           # out buf base
    mov rbx, rdi           # value
    lea r13, [num_buf+15]  # end scratch ptr
    mov rdi, r13
    test rbx, rbx
    jnz 1f
    mov byte ptr [rdi], '0'
    dec rdi
    jmp 3f
1:
    mov rax, rbx
2:
    test rax, rax
    jz 3f
    xor rdx, rdx
    mov rcx, 10
    div rcx
    add dl, '0'
    mov [rdi], dl
    dec rdi
    jmp 2b
3:
    inc rdi                 # rdi now points to first digit
    lea rcx, [r13+1]
    sub rcx, rdi             # length
    mov rsi, rdi
    mov rdi, r12
    push rcx
4:
    test rcx, rcx
    jz 5f
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp 4b
5:
    pop rax
    pop r13
    pop r12
    pop rbx
    ret

# ---------------- main ----------------
_start:
    # ---- envp: rsp -> [argc][argv...][NULL][envp...][NULL] ----
    mov rbp, [rsp]          # argc
    lea r15, [rsp + 8 + rbp*8 + 8]   # r15 = envp

    # defaults
    lea rdi, [wm_buf]
    lea rsi, [fallback_wm]
    mov rcx, fallback_wm_len
    inc rcx
    call mcopy

    lea rdi, [shell_buf]
    mov byte ptr [rdi], '?'
    mov byte ptr [rdi+1], 0

    # ---- scan envp for SHELL=, XDG_CURRENT_DESKTOP=, DESKTOP_SESSION= ----
    mov r14, r15
6:
    mov rbx, [r14]
    test rbx, rbx
    je 9f

    mov rdi, rbx
    lea rsi, [key_shell]
    mov rdx, key_shell_len
    call str_ncmp_prefix
    test rax, rax
    jz 7f
    lea rdi, [rbx + key_shell_len]
    call basename_into_shellbuf
    jmp 8f
7:
    mov rdi, rbx
    lea rsi, [key_xdg]
    mov rdx, key_xdg_len
    call str_ncmp_prefix
    test rax, rax
    jz 71f
    lea rdi, [rbx + key_xdg_len]
    lea rsi, [wm_buf]
    call strcpy_into
    jmp 8f
71:
    mov rdi, rbx
    lea rsi, [key_dsession]
    mov rdx, key_dsession_len
    call str_ncmp_prefix
    test rax, rax
    jz 8f
    lea rdi, [rbx + key_dsession_len]
    lea rsi, [wm_buf]
    call strcpy_into
8:
    add r14, 8
    jmp 6b
9:

    # ---- read /etc/os-release, find PRETTY_NAME ----
    lea rdi, [path_osrelease]
    xor rsi, rsi            # O_RDONLY
    xor rdx, rdx
    mov rax, 2               # sys_open
    syscall
    cmp rax, 0
    jl .no_osrelease
    mov r13, rax             # fd

    lea rsi, [os_buf]
    mov rdx, 1023
    mov rdi, r13
    mov rax, 0                # sys_read
    syscall
    mov r12, rax               # bytes read

    mov rdi, r13
    mov rax, 3                 # sys_close
    syscall

    cmp r12, 0
    jle .no_osrelease

    lea rdi, [os_buf]
    mov rsi, r12
    lea rdx, [key_pretty]
    mov rcx, key_pretty_len
    call find_substr
    test rax, rax
    je .no_osrelease

    add rax, key_pretty_len
    lea rdi, [pretty_buf]
    mov rsi, rax
10:
    mov al, [rsi]
    cmp al, '"'
    je 11f
    cmp al, 0
    je 11f
    mov [rdi], al
    inc rdi
    inc rsi
    jmp 10b
11:
    mov byte ptr [rdi], 0
    jmp .have_os

.no_osrelease:
    lea rdi, [pretty_buf]
    lea rsi, [fallback_os]
    mov rcx, fallback_os_len
    inc rcx
    call mcopy

.have_os:
    # ---- uname for kernel release ----
    lea rdi, [utsname_buf]
    mov rax, 63              # sys_uname
    syscall

    # ---- sysinfo for uptime ----
    lea rdi, [sysinfo_buf]
    mov rax, 99               # sys_sysinfo
    syscall
    mov rax, [sysinfo_buf]    # uptime in seconds (first field, long)
    call format_uptime

    # ---- print everything ----
    lea rdi, [logo1]
    mov rsi, logo1_len
    call write_n
    lea rdi, [lbl_os]
    mov rsi, lbl_len
    call write_n
    lea rdi, [pretty_buf]
    call print_cstr
    lea rdi, [nl]
    mov rsi, 1
    call write_n

    lea rdi, [logo2]
    mov rsi, logo2_len
    call write_n
    lea rdi, [lbl_kernel]
    mov rsi, lbl_len
    call write_n
    lea rdi, [utsname_buf + 130]   # release field offset (2*65)
    call print_cstr
    lea rdi, [nl]
    mov rsi, 1
    call write_n

    lea rdi, [logo3]
    mov rsi, logo3_len
    call write_n
    lea rdi, [lbl_uptime]
    mov rsi, lbl_len
    call write_n
    lea rdi, [uptime_str]
    call print_cstr
    lea rdi, [nl]
    mov rsi, 1
    call write_n

    lea rdi, [logo4]
    mov rsi, logo4_len
    call write_n
    lea rdi, [lbl_shell]
    mov rsi, lbl_len
    call write_n
    lea rdi, [shell_buf]
    call print_cstr
    lea rdi, [nl]
    mov rsi, 1
    call write_n

    lea rdi, [logo5]
    mov rsi, logo5_len
    call write_n
    lea rdi, [lbl_wm]
    mov rsi, lbl_len
    call write_n
    lea rdi, [wm_buf]
    call print_cstr
    lea rdi, [nl]
    mov rsi, 1
    call write_n

    lea rdi, [logo6]
    mov rsi, logo6_len
    call write_n
    lea rdi, [nl]
    mov rsi, 1
    call write_n

    lea rdi, [logo7]
    mov rsi, logo7_len
    call write_n
    lea rdi, [nl]
    mov rsi, 1
    call write_n

    # ---- exit(0) ----
    xor rdi, rdi
    mov rax, 60
    syscall

# ---------------- more helpers ----------------

# mcopy: rdi=dst, rsi=src, rcx=count (bytes, includes null if any)
mcopy:
1:
    test rcx, rcx
    jz 2f
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp 1b
2:
    ret

# strcpy_into: rdi=src (null or newline terminated env value), rsi=dst
strcpy_into:
1:
    mov al, [rdi]
    cmp al, 0
    je 2f
    cmp al, 10
    je 2f
    mov [rsi], al
    inc rdi
    inc rsi
    jmp 1b
2:
    mov byte ptr [rsi], 0
    ret

# basename_into_shellbuf: rdi=src (e.g. "/bin/bash"), writes basename into shell_buf
basename_into_shellbuf:
    push rdi
    call strlen
    pop rdi
    mov rcx, rax             # len
    lea rbx, [rdi + rax]     # end ptr
1:
    cmp rbx, rdi
    je 2f
    cmp byte ptr [rbx-1], '/'
    je 2f
    dec rbx
    jmp 1b
2:
    lea rsi, [shell_buf]
3:
    mov al, [rbx]
    cmp al, 0
    je 4f
    mov [rsi], al
    inc rbx
    inc rsi
    jmp 3b
4:
    mov byte ptr [rsi], 0
    ret

# format_uptime: rax = seconds -> writes "<n>d" / "<n>h" / "<n>m" into uptime_str
format_uptime:
    mov rbx, rax
    mov rcx, 86400
    cmp rbx, rcx
    jl 1f
    xor rdx, rdx
    mov rax, rbx
    div rcx
    lea rsi, [uptime_str]
    mov rdi, rax
    call itoa_unsigned
    lea rdi, [uptime_str + rax]
    mov byte ptr [rdi], 'd'
    mov byte ptr [rdi+1], 0
    ret
1:
    mov rcx, 3600
    cmp rbx, rcx
    jl 2f
    xor rdx, rdx
    mov rax, rbx
    div rcx
    lea rsi, [uptime_str]
    mov rdi, rax
    call itoa_unsigned
    lea rdi, [uptime_str + rax]
    mov byte ptr [rdi], 'h'
    mov byte ptr [rdi+1], 0
    ret
2:
    xor rdx, rdx
    mov rax, rbx
    mov rcx, 60
    div rcx
    lea rsi, [uptime_str]
    mov rdi, rax
    call itoa_unsigned
    lea rdi, [uptime_str + rax]
    mov byte ptr [rdi], 'm'
    mov byte ptr [rdi+1], 0
    ret
