mv %ax, 8
call factorial
out %ax, 0
hlt

factorial:
; (ax) -> 1*...*ax 
                mv %bx, %ax
                dec %bx
fact_loop:      mul %ax, %bx
                cmp %bx, 1
                dec %bx
                jpa fact_loop
                ret
