// 最小的執行環境：不用 C 函式庫，自己寫程式進入點和系統呼叫
// qemu-riscv32 會把 ecall 轉成 Linux 系統呼叫：a7 = 64 是 write，a7 = 93 是 exit

    .text
    .globl _start
_start:
    call  main              // main 的回傳值（失敗筆數）會在 a0
    li    a7, 93            // exit(a0)
    ecall

    .globl sys_write
    .type  sys_write, @function
sys_write:                  // a0 = fd，a1 = 字串位址，a2 = 長度
    li    a7, 64
    ecall
    ret
    .size sys_write, .-sys_write
