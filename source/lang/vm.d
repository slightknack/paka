module lang.vm;

import std.stdio;
import std.range;
import std.conv;
import std.algorithm;
import std.json;
import core.memory;
import core.stdc.stdlib;
import lang.data.array;
import lang.serial;
import lang.dynamic;
import lang.bytecode;
import lang.json;

enum string[2][] cmpMap()
{
    return [["oplt", "<"], ["opgt", ">"], ["oplte", "<="], ["opgte", ">="]];
}

enum string[2][] mutMap()
{
    return [["+=", "add"], ["-=", "sub"], ["*=", "mul"], ["/=", "div"], ["%=", "mod"]];
}

Dynamic[] glocals;

void store(string op = "=")(Dynamic[] locals, Dynamic to, Dynamic from)
{
    if (to.type == Dynamic.Type.num)
    {
        static if (op == "=")
        {
            mixin("locals[cast(size_t) to.num] = locals[cast(size_t) to.num]" ~ op ~ "from;");
        }
        else
        {
            mixin("locals[cast(size_t) to.num] = locals[cast(size_t) to.num]" ~ op ~ "from;");
        }
    }
    else if (to.type == Dynamic.Type.dat)
    {
        Dynamic arr = to.arr[0];
        static if (op == "=")
        {
            switch (arr.type)
            {
            case Dynamic.Type.arr:
                arr.arr[to.arr[1].num.to!size_t] = from;
                break;
            case Dynamic.Type.tab:
                arr.tab[to.arr[1]] = from;
                break;
            default:
                throw new Exception("error: cannot store at index");
            }
        }
        else
        {
            switch (arr.type)
            {
            case Dynamic.Type.arr:
                mixin(
                        "arr.arr[to.arr[1].num.to!size_t] = arr.arr[to.arr[1].num.to!size_t]"
                        ~ op ~ " from;");
                break;
            case Dynamic.Type.tab:
                mixin("arr.tab[to.arr[1]] = arr.tab[to.arr[1]]" ~ op ~ " from;");
                break;
            default:
                throw new Exception("error: cannot store at index");
            }
        }
    }
    else if (to.type == Dynamic.Type.str)
    {
        static if (op == "=")
        {
            locals[$ - 1].arr[$ - 1].tab[to] = from;
        }
        else
        {
            Table tab = locals[$ - 1].arr[$ - 1].tab;
            mixin("tab[to] = tab[to]" ~ op ~ " from;");
        }
    }
    else
    {
        assert(to.type == from.type);
        if (to.type == Dynamic.Type.arr)
        {
            SafeArray!Dynamic arr = from.arr;
            size_t sindex = 0;
            outwhile: while (sindex < to.arr.length)
            {
                Dynamic nto = (to.arr)[sindex];
                if (nto.type == Dynamic.Type.pac)
                {
                    sindex++;
                    size_t alen = from.arr.length - to.arr.length;
                    locals.store!op((to.arr)[sindex], dynamic(arr[sindex - 1 .. index + alen + 1]));
                    sindex++;
                    while (sindex < to.arr.length)
                    {
                        locals.store!op((to.arr)[sindex], arr[sindex + alen]);
                        sindex++;
                    }
                    break outwhile;
                }
                else
                {
                    locals.store!op(nto, arr[sindex]);
                }
                sindex++;
            }
        }
        else if (to.type == Dynamic.Type.tab)
        {
            foreach (v; to.tab.byKeyValue)
            {
                locals.store!op(v.value, (from.tab)[v.key]);
            }
        }
        else
        {
            throw new Exception("unknown error");
        }
    }
}

size_t calldepth;
Dynamic[][] stacks = new Array[1000];
Dynamic[][] localss = new Array[1000];
size_t[] indexs = new size_t[1000];
Function[] funcs = new Function[1000];
size_t[] depths = new size_t[1000];
SerialValue[string] states;

ref Dynamic[] stack()
{
    return stacks[calldepth - 1];
}

ref Dynamic[] locals()
{
    return localss[calldepth - 1];
}

ref size_t index()
{
    return indexs[calldepth - 1];
}

ref size_t depth()
{
    return depths[calldepth - 1];
}

Function func()
{
    return funcs[calldepth - 1];
}

void enterScope(Function afunc, SafeArray!Dynamic args)
{
    GC.enable;
    scope (exit)
    {
        GC.disable;
    }
    funcs[calldepth] = afunc;
    stacks[calldepth] = new Dynamic[afunc.stackSize];
    localss[calldepth] = new Dynamic[afunc.stab.byPlace.length + 1];
    indexs[calldepth] = 0;
    depths[calldepth] = 0;
    calldepth += 1;
    if (calldepth + 4 > funcs.length)
    {
        funcs.length *= 2;
        stacks.length *= 2;
        localss.length *= 2;
        indexs.length *= 2;
        depths.length *= 2;
    }
    foreach (i, v; args)
    {
        locals[i] = v;
    }
    locals[$ - 1] = dynamic(Array.init);
}

void exitScope()
{
    calldepth--;
}

size_t vmRecord;
size_t maxLength = size_t.max;

Dynamic run(bool saveLocals = false, bool hasScope = true)(Function afunc, size_t exiton = calldepth)
{
    static if (hasScope)
    {
        if (afunc !is null)
        {
            afunc.enterScope(SafeArray!Dynamic.init);
        }
        scope (exit)
        {
            if (afunc !is null)
            {
                exitScope;
            }
        }
    }
    static if (saveLocals)
    {
        scope (exit)
        {
            glocals = locals[0 .. func.stab.byPlace.length].dup;
        }
    }
    vmLoop: while (vmRecord < maxLength)
    {
        Instr cur = func.instrs[index];
        vmRecord++;
        // writeln(vmRecord, ": ", cur);
        // File("world/vm/" ~ vmRecord.to!string ~ ".json", "w").write(saveState);
        switch (cur.op)
        {
        default:
            throw new Exception("unknown error");
        case Opcode.nop:
            break;
        case Opcode.push:
            stack[depth++] = func.constants[cur.value];
            break;
        case Opcode.pop:
            depth--;
            break;
        case Opcode.data:
            stack[depth - 1].type = Dynamic.Type.dat;
            break;
        case Opcode.sub:
            Function built = new Function(func.funcs[cur.value]);
            built.captured = null;
            built.parent = func;
            foreach (i, v; built.capture)
            {
                Function.Capture cap = built.capture[i];
                if (cap.is2)
                {
                    built.captured ~= func.captured[cap.from];
                }
                else
                {
                    built.captured ~= &locals[cap.from];
                }
            }
            stack[depth++] = dynamic(built);
            break;
        case Opcode.bind:
            depth--;
            // (obj.tab)[stack[depth]].fun.pro.self = [obj];
            assert(stack[depth - 1].tab[stack[depth]].type == Dynamic.Type.pro);
            stack[depth - 1].tab[stack[depth]].fun.pro = new Function(
                    stack[depth - 1].tab[stack[depth]].fun.pro);
            stack[depth - 1].tab[stack[depth]].fun.pro.self = [stack[depth - 1]];
            stack[depth - 1] = stack[depth - 1].tab[stack[depth]];
            break;
        case Opcode.call:
            depth -= cur.value;
            Dynamic f = stack[depth - 1];
            switch (f.type)
            {
            case Dynamic.Type.fun:
                stack[depth - 1] = f.fun.fun(SafeArray!Dynamic(stack[depth .. depth + cur.value]));
                break;
            case Dynamic.Type.pro:
                enterScope(f.fun.pro,
                        SafeArray!Dynamic(f.fun.pro.self ~ stack[depth .. depth + cur.value]));
                continue vmLoop;
            default:
                throw new Exception("error: not a function: " ~ f.to!string);
            }
            break;
        case Opcode.upcall:
            size_t end = depth;
            depth--;
            while (stack[depth].type != Dynamic.Type.end)
            {
                depth--;
            }
            SafeArray!Dynamic cargs;
            for (size_t i = depth + 1; i < end; i++)
            {
                if (stack[i].type == Dynamic.Type.pac)
                {
                    i++;
                    cargs ~= stack[i].arr;
                }
                else
                {
                    cargs ~= stack[i];
                }
            }
            Dynamic f = stack[depth - 1];
            Dynamic result = void;
            switch (f.type)
            {
            case Dynamic.Type.fun:
                result = f.fun.fun(cargs);
                break;
            case Dynamic.Type.pro:
                enterScope(f.fun.pro, SafeArray!Dynamic(f.fun.pro.self ~ cargs));
                // enterScope(f.fun.pro, cargs);
                continue vmLoop;
            default:
                throw new Exception("error: not a function: " ~ f.to!string);
            }
            stack[depth - 1] = result;
            break;
        case Opcode.oplt:
            depth -= 1;
            stack[depth - 1] = dynamic(stack[depth - 1] < stack[depth]);
            break;
        case Opcode.opgt:
            depth -= 1;
            stack[depth - 1] = dynamic(stack[depth - 1] > stack[depth]);
            break;
        case Opcode.oplte:
            depth -= 1;
            stack[depth - 1] = dynamic(stack[depth - 1] <= stack[depth]);
            break;
        case Opcode.opgte:
            depth -= 1;
            stack[depth - 1] = dynamic(stack[depth - 1] >= stack[depth]);
            break;
        case Opcode.opeq:
            depth -= 1;
            stack[depth - 1] = dynamic(stack[depth - 1] == stack[depth]);
            break;
        case Opcode.opneq:
            depth -= 1;
            stack[depth - 1] = dynamic(stack[depth - 1] != stack[depth]);
            break;
        case Opcode.array:
            size_t end = depth;
            depth--;
            while (stack[depth].type != Dynamic.Type.end)
            {
                depth--;
            }
            SafeArray!Dynamic arr;
            for (size_t i = depth + 1; i < end; i++)
            {
                if (stack[i].type == Dynamic.Type.pac)
                {
                    i++;
                    arr ~= stack[i].arr;
                }
                else
                {
                    arr ~= stack[i];
                }
            }
            stack[depth] = dynamic(arr);
            depth++;
            break;
        case Opcode.targeta:
            size_t end = depth;
            depth--;
            while (stack[depth].type != Dynamic.Type.end)
            {
                depth--;
            }
            stack[depth] = dynamic(stack[depth + 1 .. end].dup);
            depth++;
            break;
        case Opcode.unpack:
            Dynamic val = dynamic(Array.init);
            val.type = Dynamic.Type.pac;
            stack[depth] = val;
            depth++;
            break;
        case Opcode.table:
            size_t end = depth;
            depth--;
            while (stack[depth].type != Dynamic.Type.end)
            {
                depth--;
            }
            // depth -= cur.value;
            Dynamic[Dynamic] table;
            size_t place = depth + 1;
            // size_t end = place + cur.value;
            while (place < end)
            {
                if (stack[place].type == Dynamic.Type.pac)
                {
                    foreach (kv; stack[place + 1].tab.byKeyValue)
                    {
                        table[kv.key] = kv.value;
                    }
                    place += 2;
                }
                else
                {
                    table[stack[place]] = stack[place + 1];
                    place += 2;
                }
            }
            // stack[depth] = dynamic(stack[depth .. end]);
            stack[depth] = dynamic(table);
            depth++;
            break;
        case Opcode.index:
            depth--;
            Dynamic arr = stack[depth - 1];
            switch (arr.type)
            {
            case Dynamic.Type.arr:
                stack[depth - 1] = (arr.arr)[stack[depth].num.to!size_t];
                break;
            case Dynamic.Type.tab:

                if (stack[depth]!in arr.tab)
                {
                    throw new Exception("index error: " ~ stack[depth].to!string ~ " not found");
                }
                stack[depth - 1] = (arr.tab)[stack[depth]];
                break;
            default:
                throw new Exception("error: cannot get index from: " ~ arr.to!string);
            }
            break;
        case Opcode.opneg:
            stack[depth - 1] = -stack[depth - 1];
            break;
        case Opcode.opadd:
            depth--;
            stack[depth - 1] = stack[depth - 1] + stack[depth];
            break;
        case Opcode.opsub:
            depth--;
            stack[depth - 1] = stack[depth - 1] - stack[depth];
            break;
        case Opcode.opmul:
            depth--;
            stack[depth - 1] = stack[depth - 1] * stack[depth];
            break;
        case Opcode.opdiv:
            depth--;
            stack[depth - 1] = stack[depth - 1] / stack[depth];
            break;
        case Opcode.opmod:
            depth--;
            stack[depth - 1] = stack[depth - 1] % stack[depth];
            break;
        case Opcode.load:
            stack[depth++] = locals[cur.value];
            break;
        case Opcode.loadc:
            stack[depth++] = *func.captured[cur.value];
            break;
        case Opcode.store:
            locals[cur.value] = stack[depth - 1];
            break;
        case Opcode.istore:
            switch (stack[depth - 2].type)
            {
            case Dynamic.Type.arr:
                stack[depth - 1] = stack[depth - 2].arr[stack[depth - 1].num.to!size_t]
                    = stack[depth - 3];
                break;
            case Dynamic.Type.tab:
                stack[depth - 1] = stack[depth - 2].tab[stack[depth - 1]] = stack[depth - 3];
                break;
            default:
                throw new Exception("error: cannot store at index");
            }
            depth -= 1;
            break;
        case Opcode.tstore:
            depth -= 2;
            locals.store(stack[depth + 1], stack[depth]);
            depth++;
            break;
        case Opcode.qstore:
            depth -= 1;
            locals[$ - 1].arr[$ - 1].tab[dynamic(stack[depth].str)] = stack[depth - 1];
            break;
        case Opcode.opstore:
        switchOpp:
            switch (func.instrs[++index].value)
            {
            default:
                throw new Exception("unknown error");
                static foreach (opm; mutMap)
                {
            case opm[1].to!AssignOp:
                    stack[depth - 1] = mixin("locals[cur.value]" ~ opm[0] ~ " stack[depth - 1]");
                    break switchOpp;
                }
            }
            break;
        case Opcode.opistore:
        switchOpi:
            switch (func.instrs[index].value)
            {
            default:
                throw new Exception("unknown error");
                static foreach (opm; mutMap)
                {
            case opm[1].to!AssignOp:
                    Dynamic arr = stack[depth - 2];
                    switch (arr.type)
                    {
                    case Dynamic.Type.arr:
                        stack[depth - 3] = mixin(
                                "arr.arr[stack[depth-1].num.to!size_t]" ~ opm[0] ~ " stack[depth-3]");
                        break switchOpi;
                    case Dynamic.Type.tab:
                        stack[depth - 3] = mixin(
                                "arr.tab[stack[depth-1]]" ~ opm[0] ~ " stack[depth-3]");
                        break switchOpi;
                    default:
                        throw new Exception("error: cannot store at index");
                    }
                }
            }
            depth -= 2;
            break;
        case Opcode.optstore:
            depth -= 2;
        switchOpt:
            switch (cur.value)
            {
            default:
                throw new Exception("unknown error");
                static foreach (opm; mutMap)
                {
            case opm[1].to!AssignOp:
                    locals.store!(opm[0])(stack[depth + 1], stack[depth]);
                    break switchOpt;
                }
            }
            depth++;
            break;
        case Opcode.opqstore:
            depth -= 1;
        switchOpq:
            switch (func.instrs[++index].value)
            {
            default:
                throw new Exception("unknown error");
                static foreach (opm; mutMap)
                {
            case opm[1].to!AssignOp:
                    stack[depth - 1] = mixin(
                            "locals[$ - 1].arr[$ - 1].tab[dynamic(stack[depth].str)]"
                            ~ opm[0] ~ " stack[depth - 1]");
                    break switchOpq;
                }
            }
            break;
        case Opcode.retval:
            Dynamic v = stack[--depth];
            if (calldepth - 1 == exiton)
            {
                return v;
            }
            exitScope;
            stack[depth - 1] = v;
            break;
        case Opcode.retnone:
            if (calldepth - 1 == exiton)
            {
                return Dynamic.nil;
            }
            exitScope;
            stack[depth - 1] = Dynamic.nil;
            break;
        case Opcode.iftrue:
            Dynamic val = stack[--depth];
            if (val.type != Dynamic.Type.nil && (val.type != Dynamic.Type.log || val.log))
            {
                index = cur.value;
            }
            break;
        case Opcode.iffalse:
            Dynamic val = stack[--depth];
            if (val.type == Dynamic.Type.nil || (val.type == Dynamic.Type.log && !val.log))
            {
                index = cur.value;
            }
            break;
        case Opcode.jump:
            index = cur.value;
            break;
        }
        index++;
    }
    throw new Exception("too many instructions for repl");
}
