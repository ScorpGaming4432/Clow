mult_f:
    d := 4048f5c3 "PI"
    e := 402df854 "EULER"

    @x86 mulss d, e
    goto EOF
;

add:
    t := c
    c ^ b
    b & t
    b << 1

    b? goto add
    goto end_add
;

_start:
    a := 67
    b := 02 
    c := FF

    
    goto add
    end_add:

    goto mult_f

; "MEMORY RESULT:
     (didn't check yet, wyjebane bongo)
retains raw memory (for as long as possible), pointers to addresses of starts of variables; so you can see the final values in memory after the operations are performed."