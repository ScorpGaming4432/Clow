# Language Specification — Draft 0.1
> Living document. Incomplete by design.

---

## 1. Philosophy

- No hidden control flow
- No types — the programmer knows what they're writing
- No call stack — control flow is entirely `goto`-based
- No function signatures — labels are not functions
- All magic numbers in hexadecimal only
- Target audience: masochists

---

## 2. Architecture Pragma

```
@nasm
```

Declares the target ISA for the file. Determines which mnemonics are valid as raw instructions.
Planned: macro system TBD.

---

## 3. Token Types

| Token | Description |
|---|---|
| `@` | Architecture pragma prefix |
| `:` | Opens a definition |
| `=` | Closes a definition / assigns a result |
| `;` | Terminates a label scope |
| `?` | Conditional — if true, execute next token or block. Whitespace-agnostic: `b? goto add` and `b?\ngoto add` are identical after tokenization |
| `goto` | Unconditional jump to label |
| `EOF` | End-of-program label, global state dump |
| `_start` | Required entry point label |
| `<ident>` | Label name, variable name, or ISA mnemonic |
| `<hex>` | Numeric literal — hex only (e.g. `FF`, `4A`) |
| `"..."` | Comment |

---

## 4. Definition Syntax

`:` opens a definition. `=` closes it and assigns a result.
The content between them determines what kind of definition it is.

### 4.1 Variable (immediate assignment)

```
a:=FF
```

`:` opens, `=` immediately closes with value `FF`. No body.
All variables are fixed-size, known at compile time.
Size is TBD — likely determined by the value or by explicit annotation.

**Variable naming convention:**
- Lowercase only
- Exactly 1 character
- Range: ASCII `a` to `p` (16 variables total)
- Maps directly to the 16 general-purpose registers of the target ISA (e.g. x86-64: `rax`–`r15`)
- Variables live in registers during execution — no dereference cost at runtime
- At `EOF`, all registers are flushed to a fixed pointer table in memory for external programs to read
- Register allocation is a compile-time no-op — the mapping is fixed, no graph coloring needed

**Hazardous register mappings (x86-64):**
| Variable | Register | Hazard |
|---|---|---|
| `c` | `rcx` | Clobbered by `syscall` |
| `d` | `rdx` | Holds syscall arg 3 |
| `p` | `r15` | Callee-saved — safe but notable |

The programmer is responsible for knowing these. No warnings emitted.

Any identifier longer than 1 character, or outside `a`–`p`, is treated as a **label** (constant by default). Labels are immutable unless the user explicitly writes self-modifying code.

### 4.2 Label (with body and result)

```
label:
  <instructions>
= result
;
```

`:` opens the label body. `=` provides the result value. `;` closes the label scope.
If execution reaches `;` without hitting `=`, the address of `;` is treated as an error sentinel (`z`).

### 4.3 Named Constant (degenerate label)

```
label:
= FF
;
```

Falls out of the grammar naturally — a label with no body, just a result. Effectively a named constant.

---

## 5. Control Flow

No call stack. No return addresses. All control flow is explicit.

### 5.1 Unconditional jump

```
goto label
```

### 5.2 Conditional jump

```
b? goto add
goto end_add
```

`?` evaluates the preceding value or flag. If **true**, the immediately following statement executes. If **false**, it is skipped and execution continues at the statement after.

Whitespace is irrelevant — the tokenizer splits on any whitespace, so the following are identical:

```
b? goto add

b?
goto add
```

`?` can also open a block with `?:` for multi-instruction conditional bodies:

```
b ?:
  goto add
  goto somewhere
;
```

### 5.3 EOF as return

```
EOF
```

Required label. When reached, all variables are preserved at a known address. External programs can read the state by knowing the memory layout. No return value mechanism beyond this.

---

## 6. Operations

All operations follow the form:

```
x op y
```

Which the compiler maps to `x = x op y`. The result is always stored back into the left operand. There is no pure expression that goes nowhere — every operation is an implicit in-place assignment.

**Natively recognised by the compiler (bitwise only):**

| Syntax | Operation |
|---|---|
| `x & y` | AND |
| `x \| y` | OR |
| `x ^ y` | XOR |
| `x << y` | Left shift |
| `x >> y` | Right shift |

All arithmetic, floating point, and anything else is either user-defined via labels or written as raw ISA mnemonics. The compiler has no knowledge of `+`, `-`, `*`, `/` etc.

> Note: XNOR (equality) is not a separate operator. The programmer composes it from `x ^ y` followed by bitwise NOT, or uses raw ISA mnemonics directly.

---

## 7. Raw ISA Instructions

Any identifier not recognised as a language keyword is treated as an ISA mnemonic for the declared `@architecture`.

```
mov eax, ebx
cmp rax, 0x01
```

Operand syntax follows the target assembler's conventions (NASM by default).

> Resolution: on encountering `@arch`, the compiler immediately loads the full ISA mnemonic table for that architecture. During parsing, any bare identifier is looked up in this table first. If it matches, it is an instruction node. If not, it is a label or variable.

---

## 8. Memory

- Variables live in registers during execution (`a`=`rax` … `p`=`r15`)
- At `EOF`, all registers are flushed to a fixed 128-byte pointer table in memory (16 entries × 8 bytes)
- External programs read from this table — each entry is a pointer to the variable's actual data
- Actual data is packed contiguously in a `.data`-equivalent section, sized by literal width at definition time
- A `malloc`-equivalent is planned — returns a raw pointer, no metadata, no header
- The programmer is responsible for knowing how many bytes to read back
- No garbage collection, no ownership model

**Size inference from hex literals:**

| Literal length (nibbles) | Bytes allocated |
|---|---|
| 1–2 | 1 |
| 3–4 | 2 |
| 5–8 | 4 |
| 9–16 | 8 |

Odd-length literals are zero-padded left (e.g. `ABC` → `0ABC` → 2 bytes). TBD whether to require even-length literals instead.

---

## 9. Program Structure

```
@arch

_start:
  <instructions>
;

EOF
```

- `@arch` must appear first
- `_start` is the mandatory entry point
- `EOF` must appear at the end
- Label order in source does not affect correctness — compiler resolves all addresses before emission (two-pass)

---

## 10. Undefined Behaviour

The compiler does not check for semantic errors. It trusts the programmer entirely and emits bytes corresponding to what was written. The CPU is the final arbiter of what happens.

### 10.1 Possible outcomes of malformed code

| Situation | Likely outcome |
|---|---|
| Unrecognised opcode bytes | `SIGILL` — CPU raises illegal instruction exception, OS kills process |
| Operands that decode as valid opcodes | CPU executes them as instructions — silent, unpredictable |
| Jump to unmapped/wrong address | `SIGSEGV` — process killed |
| Valid instruction, wrong registers | Silent state corruption — program continues, nothing visibly wrong |
| Malformed conditional block in executable memory | Data interpreted as code by CPU — self-inflicted self-modifying code |

### 10.2 Design position

C's undefined behaviour is dangerous because the compiler *assumes* it never happens and optimises accordingly, producing surprising transformations. This language makes no such assumptions — it emits what is written. The unpredictability is therefore *honest*: it comes from the hardware, not from compiler cleverness.

### 10.3 Intentional undefined behaviour (planned)

An interesting design exercise: deliberately expose undefined behaviour as a feature rather than a footnote. Possible directions:

- A pragma or sigil that tells the compiler to **intentionally corrupt** the instruction stream in a deterministic but opaque way — reproducible chaos
- Allowing the programmer to **emit raw bytes directly** with no mnemonic validation, bypassing even the ISA table
- A `?:` block with **no closing delimiter** — the CPU decides where the block ends based on whatever bytes follow
- Deliberate misaligned jumps into the middle of a multibyte instruction, producing a different valid instruction as a side effect

> The boundary between "undefined behaviour" and "self-modifying code" in this language is intentionally thin.

---

## 11. Open Questions

1. **`=` ambiguity** — `=` as definition-close vs `:=` assignment vs in-place op result. Likely resolvable by context: `:=` is always assignment, bare `=` at statement level is always definition-close. Needs formalising in grammar.
2. ~~**Identifier vs mnemonic**~~ — resolved. Pragma loads ISA table; identifiers are matched against it at parse time.
3. ~~**Variable size**~~ — resolved. Inferred from hex literal width, rounded up to nearest power-of-two byte count. Odd-length literals zero-padded left.
4. ~~**Forward references**~~ — resolved. Two-pass compilation. First pass collects all label addresses, second pass emits. Label order in source is irrelevant.
5. **Nested definitions** — `a : b:=FF = b` is grammatically valid under current rules. Confirmed intentional — valid obfuscation technique.
6. **Hex literal syntax** — bare (`FF`) or prefixed (`0xFF`)? Bare preferred aesthetically. Lexer disambiguation rule needed — likely: a hex literal must start with a digit (`0`–`9`) to distinguish from identifiers. So `FF` would need to be `0FF` or `0xFF`. TBD.
7. **Macro system** — noted as planned, design TBD.
8. ~~**Comparison operators**~~ — resolved. Equality is user-implemented via bitwise ops (XNOR). No special comparison syntax. `?` tests a value or flag; setup is the programmer's responsibility.
9. **XMM / FPU registers** — `a`–`p` map to general-purpose registers only. Floating point requires either raw ISA mnemonics with explicit XMM register names, or a user-implemented float multiplier in bitwise ops. No language-level float support planned.
