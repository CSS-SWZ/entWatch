"""
Проверка рефакторинга «только перенос» для entWatch.

Прогоняет упрощённый препроцессор SourcePawn по entWatch.sp для каждого сочетания
define'ов модулей, разбирает единицу трансляции на символы верхнего уровня
(функции, глобальные переменные, define'ы, enum / enum struct, директивы) и сравнивает
базовую ревизию git с рабочим деревом:

  1. у каждого символа совпадают текст (с комментарием над ним, пробелы нормализованы)
     и набор сборок, в которые он попадает;
  2. глобальная переменная, define, тип или константа enum не используются раньше
     своего объявления (в SourcePawn это ошибка компиляции, функции — нет);
  3. ни один символ плагина не используется в сборке, где его нет (например, сборка без
     модуля зовёт функцию модуля). Нативы и символы SourceMod не проверяются: include'ы
     SourceMod скрипт не разбирает.

Это не замена компилятору: разбор приблизительный. Но перенос функции из файла в файл,
потерю или правку символа и сломанный порядок include'ов он ловит.

Запуск из корня репозитория:
    python docs/restructure/tools/symbols.py                  # HEAD против рабочего дерева
    python docs/restructure/tools/symbols.py --base master~1
    python docs/restructure/tools/symbols.py --allow ClientAuth --allow RestrictOnClientAuth
"""

import argparse
import itertools
import os
import re
import subprocess
import sys

SCRIPTING = "addons/sourcemod/scripting"
ENTRY = "entWatch.sp"
LOCAL_INCLUDE = "include"

# Define'ы, которые перебираются. Их собственные #define в исходниках игнорируются:
# значение задаёт перебор. _zr_included — наличие zombiereloaded.inc (#tryinclude).
TOGGLES = ["BOTOX_SM", "HUD", "ASSIST_USE", "ADMIN_MENU", "HALFZOMBIE", "RESTRICT_BUILTIN", "_zr_included"]


# --------------------------------------------------------------------------- чтение

class Source:
    def __init__(self, rev):
        self.rev = rev  # None — рабочее дерево
        self.cache = {}

    def read(self, path):
        path = path.replace("\\", "/")
        if path not in self.cache:
            self.cache[path] = self._read(path)
        return self.cache[path]

    def _read(self, path):
        if self.rev is None:
            full = os.path.join(SCRIPTING, path)
            if not os.path.isfile(full):
                return None
            with open(full, "rb") as f:
                data = f.read()
        else:
            r = subprocess.run(["git", "show", f"{self.rev}:{SCRIPTING}/{path}"],
                               capture_output=True)
            if r.returncode != 0:
                return None
            data = r.stdout
        text = data.decode("utf-8-sig", errors="replace")
        return text.replace("\r\n", "\n").replace("\r", "\n")


def mask(text):
    """Комментарии и содержимое строк/символов — пробелы; переводы строк сохраняются."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        nx = text[i + 1] if i + 1 < n else ""
        if c == "/" and nx == "/":
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
        elif c == "/" and nx == "*":
            out.append("  ")
            i += 2
            while i < n and not (text[i] == "*" and i + 1 < n and text[i + 1] == "/"):
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            out.append("  ")
            i += 2
        elif c in "\"'":
            q = c
            out.append(q)
            i += 1
            while i < n and text[i] != q:
                if text[i] == "\\" and i + 1 < n:
                    out.append(" " if text[i + 1] != "\n" else "\n")
                    out.append(" ")
                    i += 2
                    continue
                if text[i] == "\n":  # незакрытая строка — не тянем дальше
                    break
                out.append(" ")
                i += 1
            if i < n and text[i] == q:
                out.append(q)
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


# --------------------------------------------------------------------------- препроцессор

def eval_cond(expr, defined):
    e = expr.strip()
    e = re.sub(r"\bdefined\s*\(\s*(\w+)\s*\)", r"defined \1", e)
    e = re.sub(r"\bdefined\s+(\w+)", lambda m: "True" if m.group(1) in defined else "False", e)
    e = e.replace("||", " or ").replace("&&", " and ")
    e = re.sub(r"!(?!=)", " not ", e)
    try:
        return bool(eval(e, {"__builtins__": {}}, {}))
    except Exception:
        raise SystemExit(f"не разобрать условие препроцессора: #if {expr}")


class Line:
    __slots__ = ("raw", "code", "file", "no", "cond")

    def __init__(self, raw, code, file, no, cond):
        self.raw, self.code, self.file, self.no, self.cond = raw, code, file, no, cond


def preprocess(src, defines):
    """Активные строки единицы трансляции в порядке компиляции."""
    defined = set(defines)
    lines = []
    seen_once = set()

    def run(path, cond_prefix):
        text = src.read(path)
        if text is None:
            raise SystemExit(f"[{src.rev or 'worktree'}] не найден include: {path}")
        raw_lines = text.split("\n")
        code_lines = mask(text).split("\n")
        stack = []  # (родитель активен, ветка активна, ветка уже была, условие)
        active = True
        base_dir = os.path.dirname(path)
        i = 0
        while i < len(code_lines):
            code = code_lines[i]
            raw = raw_lines[i]
            no = i + 1
            # склейка строк с '\' в конце
            while code.rstrip().endswith("\\") and i + 1 < len(code_lines):
                i += 1
                code = code.rstrip()[:-1] + " " + code_lines[i]
                raw = raw + "\n" + raw_lines[i]
            i += 1
            s = code.strip()
            m = re.match(r"#\s*(\w+)\s*(.*)", s)
            if m:
                d, arg = m.group(1), m.group(2).strip()
                if d == "if":
                    val = eval_cond(arg, defined)
                    stack.append((active, active and val, val, arg))
                    active = active and val
                    continue
                if d in ("elseif", "else"):
                    parent, _, taken, c0 = stack.pop()
                    val = (not taken) and (d == "else" or eval_cond(arg, defined))
                    stack.append((parent, parent and val, taken or val, c0))
                    active = parent and val
                    continue
                if d == "endif":
                    parent = stack.pop()[0]
                    active = parent
                    continue
                if not active:
                    continue
                if d == "endinput":
                    return
                if d == "define":
                    name = re.match(r"(\w+)", arg).group(1)
                    if name in TOGGLES:
                        continue  # значение задаёт перебор
                    defined.add(name)
                elif d == "undef":
                    defined.discard(arg.split()[0])
                elif d in ("include", "tryinclude"):
                    rm = re.search(r'"([^"]+)"', raw)
                    am = re.search(r"<([^>]+)>", raw)
                    if rm:
                        target = os.path.normpath(os.path.join(base_dir, rm.group(1))).replace("\\", "/")
                        if src.read(target) is None and d == "tryinclude":
                            continue
                        run(target, cond_prefix)
                        continue
                    if am:
                        name = am.group(1)
                        inc = f"{LOCAL_INCLUDE}/{name}" + ("" if name.endswith(".inc") else ".inc")
                        if src.read(inc) is not None:
                            if inc not in seen_once:
                                seen_once.add(inc)
                                run(inc, cond_prefix)
                        # системные include'ы (sourcemod, zombiereloaded) не разбираем
                        continue
                lines.append(Line(raw, s, path, no, None))
                continue
            if active:
                lines.append(Line(raw, code, path, no, None))

    run(ENTRY, ())
    return lines, defined


# --------------------------------------------------------------------------- символы

KEYWORDS = {"if", "for", "while", "switch", "return", "case", "else", "do", "delete",
            "new", "view_as", "sizeof", "public", "static", "stock", "const", "native", "forward"}


def item_names(header_code):
    """(вид, имена) для элемента верхнего уровня по его замаскированному тексту."""
    h = " ".join(header_code.split())
    m = re.match(r"#\s*define\s+(\w+)", h)
    if m:
        return "define", [m.group(1)]
    if h.startswith("#"):
        return "directive", [h]
    m = re.match(r"enum\s+struct\s+(\w+)", h)
    if m:
        return "type", [m.group(1)]
    m = re.match(r"methodmap\s+(\w+)", h)
    if m:
        return "type", [m.group(1)]
    m = re.match(r"enum\b\s*(\w*)[^{]*\{(.*)\}", h)
    if m:
        consts = re.findall(r"(?:^|,)\s*(\w+)", m.group(2))
        names = [c for c in consts if c]
        if m.group(1):
            names = [m.group(1)] + names
        return "enum", names
    brace = h.find("{")
    head = h if brace == -1 else h[:brace]
    paren = head.find("(")
    eq = head.find("=")
    if paren != -1 and (eq == -1 or paren < eq):
        m = re.search(r"(\w+)\s*\($", head[:paren + 1])
        if m and m.group(1) not in KEYWORDS:
            return "func", [m.group(1)]
    decl = head if eq == -1 else head[:eq]
    decl = re.sub(r"\[[^\]]*\]", "", decl).rstrip("; ")
    parts = decl.split(",")
    names = []
    first = re.findall(r"\w+", parts[0])
    if first:
        names.append(first[-1])
    for p in parts[1:]:
        w = re.findall(r"\w+", p)
        if w:
            names.append(w[-1])
    return "global", names


def split_items(lines):
    """Элементы верхнего уровня: (вид, имена, нормализованный текст, файл, строка, индекс, код без комментариев)."""
    items = []
    pending_comment = []
    i = 0
    n = len(lines)
    while i < n:
        ln = lines[i]
        if not ln.code.strip():
            if ln.raw.strip():  # строка-комментарий
                pending_comment.append(ln.raw.strip())
            else:
                pending_comment = []
            i += 1
            continue
        start = i
        if ln.code.strip().startswith("#"):
            chunk = [ln]
            i += 1
        else:
            depth = 0
            opened = False
            chunk = []
            while i < n:
                cur = lines[i]
                chunk.append(cur)
                i += 1
                c = cur.code
                if c.strip().startswith("#"):
                    continue
                depth += c.count("{") - c.count("}")
                if "{" in c:
                    opened = True
                if depth <= 0 and (opened or c.rstrip().endswith(";")):
                    # "Type name = { ... };" и функции без ';' — одинаково
                    if opened and i < n and lines[i].code.strip() == ";":
                        chunk.append(lines[i])
                        i += 1
                    break
                if not opened and depth == 0 and not c.rstrip().endswith(";") and i < n:
                    # заголовок функции на одной строке, '{' на следующей
                    continue
        code = "\n".join(c.code for c in chunk)
        kind, names = item_names(code)
        text = " ".join((" ".join(pending_comment) + " " + "\n".join(c.raw for c in chunk)).split())
        items.append((kind, names, text, lines[start].file, lines[start].no, len(items), code))
        pending_comment = []
    return items


def analyze(src, defines):
    lines, _ = preprocess(src, defines)
    items = split_items(lines)
    symbols = {}
    for kind, names, text, file, no, idx, _ in items:
        for name in names:
            key = (kind, name)
            if key in symbols and kind != "directive":
                key = (kind, f"{name}#{sum(1 for k in symbols if k[1].split('#')[0] == name)}")
            symbols[key] = (text, file, no, idx)
    order_errors = check_order(items)
    defined = set()
    uses = []
    ident = re.compile(r"(?<![.\w])([A-Za-z_]\w*)")
    for kind, names, text, file, no, idx, code in items:
        if kind == "directive":
            continue
        defined.update(names)
        uses.append((set(ident.findall(code)) - set(names), file, names[0] if names else "?"))
    return symbols, order_errors, defined, uses


def check_undefined(defined, uses, plugin_names):
    """Символы плагина (есть хоть в какой-то сборке), которых нет в этой сборке, но они используются."""
    errors = set()
    for used, file, user in uses:
        for nm in (used & plugin_names) - defined:
            errors.add((nm, file, user))
    return errors


def check_order(items):
    """Не-функции, использованные в элементе, стоящем раньше объявления."""
    decl_pos = {}
    for kind, names, text, file, no, idx, _ in items:
        if kind in ("global", "define", "type", "enum"):
            for nm in names:
                decl_pos.setdefault(nm, (idx, file, no))
    errors = set()
    ident = re.compile(r"(?<![.\w])([A-Za-z_]\w*)")
    for kind, names, text, file, no, idx, code in items:
        if kind == "directive":
            continue
        used = set(ident.findall(code))
        for nm in used:
            d = decl_pos.get(nm)
            if d and d[0] > idx:
                errors.add((nm, d[1], file, names[0] if names else "?"))
    return errors


# --------------------------------------------------------------------------- сравнение

def combos(fixed):
    for bits in itertools.product([False, True], repeat=len(TOGGLES)):
        combo = frozenset(t for t, b in zip(TOGGLES, bits) if b)
        if all((name in combo) == value for name, value in fixed.items()):
            yield combo


def label(combo):
    return "{" + ", ".join(t for t in TOGGLES if t in combo) + "}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="HEAD", help="ревизия git для сравнения (по умолчанию HEAD)")
    ap.add_argument("--work", default=None, help="ревизия git вместо рабочего дерева (для сравнения коммитов)")
    ap.add_argument("--allow", action="append", default=[],
                    help="символ, изменение которого запланировано в этом шаге (можно несколько раз)")
    ap.add_argument("--fix", action="append", default=[], metavar="NAME=0|1",
                    help="сравнивать только сборки с этим значением define'а (можно несколько раз)")
    ap.add_argument("--verbose", action="store_true", help="печатать сочетания define'ов у каждого расхождения")
    args = ap.parse_args()

    fixed = {}
    for f in args.fix:
        name, _, value = f.partition("=")
        if name not in TOGGLES or value not in ("0", "1"):
            raise SystemExit(f"--fix {f}: ожидается NAME=0|1, NAME из {TOGGLES}")
        fixed[name] = value == "1"

    base_src = Source(args.base)
    work_src = Source(args.work)

    diffs = {}          # (вид, имя, что) -> [сочетания]
    order_new = {}      # ошибка порядка -> [сочетания]
    undefined_new = {}  # использование отсутствующего символа -> [сочетания]
    moved = {}          # (вид, имя) -> (было, стало)
    total = 0

    results = []
    plugin_names = set()
    for combo in combos(fixed):
        b = analyze(base_src, combo)
        w = analyze(work_src, combo)
        plugin_names |= b[2] | w[2]
        results.append((combo, b, w))

    for combo, (b_syms, b_order, b_def, b_uses), (w_syms, w_order, w_def, w_uses) in results:
        total += 1
        b_undef = check_undefined(b_def, b_uses, plugin_names)
        for err in check_undefined(w_def, w_uses, plugin_names) - b_undef:
            undefined_new.setdefault(err, []).append(combo)
        for key in set(b_syms) | set(w_syms):
            b = b_syms.get(key)
            w = w_syms.get(key)
            if b and not w:
                what = "удалён или выпал из этой сборки"
            elif w and not b:
                what = "добавлен или попал в эту сборку"
            elif b[0] != w[0]:
                what = "изменён текст"
            else:
                if b[1] != w[1]:
                    moved[key] = (b[1], w[1])
                continue
            diffs.setdefault((key[0], key[1], what), []).append(combo)
        for err in w_order - b_order:
            order_new.setdefault(err, []).append(combo)

    allowed = set(args.allow)
    unexpected = 0

    fixed_note = ", ".join(f"{k}={int(v)}" for k, v in fixed.items())
    print(f"База: {args.base}; сравнивается: {args.work or 'рабочее дерево'}; сравнено сборок: {total}"
          f" (перебор {', '.join(TOGGLES)}{'; зафиксировано ' + fixed_note if fixed_note else ''})\n")

    if moved:
        print("Перенесены без изменений:")
        for (kind, name), (a, b) in sorted(moved.items(), key=lambda x: (x[1], x[0])):
            if kind == "directive":
                continue
            print(f"  {kind:6} {name:40} {a} -> {b}")
        print()

    if diffs:
        print("Расхождения:")
        for (kind, name, what), cs in sorted(diffs.items(), key=lambda x: (x[0][1], x[0][0])):
            base_name = name.split("#")[0]
            mark = "  (разрешено)" if base_name in allowed else ""
            if not mark:
                unexpected += 1
            scope = "во всех сборках" if len(cs) == total else f"в {len(cs)} из {total} сборок"
            print(f"  {kind:9} {name:40} {what}, {scope}{mark}")
            if args.verbose and len(cs) != total:
                for c in cs[:8]:
                    print(f"            {label(c)}")
                if len(cs) > 8:
                    print(f"            … ещё {len(cs) - 8}")
        print()

    if order_new:
        print("Использование раньше объявления (новое относительно базы):")
        for (name, dfile, ufile, user), cs in sorted(order_new.items()):
            unexpected += 1
            scope = "во всех сборках" if len(cs) == total else f"в {len(cs)} из {total} сборок"
            print(f"  {name} (объявлен в {dfile}) используется раньше в {ufile}, {user}; {scope}")
        print()

    if undefined_new:
        print("Используется символ, которого нет в этой сборке (новое относительно базы):")
        for (name, ufile, user), cs in sorted(undefined_new.items()):
            unexpected += 1
            scope = "во всех сборках" if len(cs) == total else f"в {len(cs)} из {total} сборок"
            print(f"  {name} — в {ufile}, {user}; {scope}")
            if args.verbose and len(cs) != total:
                for c in cs[:8]:
                    print(f"            {label(c)}")
        print()

    if unexpected:
        print(f"ИТОГ: {unexpected} незапланированных расхождений.")
        sys.exit(1)
    print("ИТОГ: только перенос; незапланированных расхождений нет.")


if __name__ == "__main__":
    main()
