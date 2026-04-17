print:
t:=00
t:= *text
t+b
&t
t? goto end_print
<syscall to stdout idk> t
b+1
goto print
;

_start:
text:= 48656C6C6F2C576F726C642100
b:= 00
goto print
end_print:;

;
EOF
