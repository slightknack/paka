module lang.bytecode;

import lang.dynamic;
import lang.srcloc;
import lang.error;
import std.stdio;

class Function
{
    struct Lookup
    {
        uint[string] byName;
        string[] byPlace;
        void clear()
        {
            byName = null;
            byPlace = null;
        }

        void set(string name, uint us)
        {
            byName[name] = us;
            byPlace ~= name;
        }

        uint define(string name)
        {
            uint ret = cast(uint)(byPlace.length);
            set(name, ret);
            return ret;
        }

        uint opIndex(string name)
        {
            return byName[name];
        }

        string opIndex(uint name)
        {
            return byPlace[name];
        }
    }

    struct Capture
    {
        uint from;
        bool is2;
    }

    enum Flags : ubyte
    {
        isLocal = 1,
    }

    Capture[] capture = null;
    ubyte[] instrs = null;
    Span[] spans = null;
    Dynamic[] constants = null;
    Function[] funcs = null;
    Dynamic*[] captured = null;
    size_t stackSize = 0;
    Dynamic[] self = null;

    Lookup stab;
    Lookup captab;
    Function parent = null;
    Flags flags = cast(Flags) 0;

    this()
    {
    }

    this(Function other)
    {
        capture = other.capture;
        instrs = other.instrs;
        spans = other.spans;
        constants = other.constants;
        funcs = other.funcs;
        parent = other.parent;
        captured = other.captured;
        stackSize = other.stackSize;
        self = other.self.dup;
        stab = other.stab;
        captab = other.captab;
        flags = other.flags;
    }

    uint doCapture(string name)
    {
        uint* got = name in captab.byName;
        if (got !is null)
        {
            return *got;
        }
        uint ret = captab.define(name);
        if (name in parent.stab.byName)
        {
            capture ~= Capture(parent.stab.byName[name], false);
            return ret;
        }
        else if (name in parent.captab.byName)
        {
            capture ~= Capture(parent.captab.byName[name], true);
            return ret;
        }
        else
        {
            if (parent.parent is null)
            {
                throw new UndefinedException("name not found: " ~ name);
            }
            parent.doCapture(name);
            capture ~= Capture(parent.captab.byName[name], true);
            return ret;
        }
    }

    override string toString()
    {
        return "<function>";
    }
}

enum AssignOp : ubyte
{
    add,
    sub,
    mul,
    div,
    mod,
}

enum Opcode : ubyte
{
    // never generated
    nop,
    // stack ops
    push,
    pop,
    // change data flag
    data,
    // subroutine
    sub,
    // bind not implmented yet
    bind,
    // call without spread
    call,
    // call with atleast 1 spread
    upcall,
    // cmp
    oplt,
    opgt,
    oplte,
    opgte,
    opeq,
    opneq,
    // build array
    array,
    // unpack into array
    unpack,
    // built table
    table,
    // index table or array
    index,
    // math ops (arithmatic)
    opneg,
    opadd,
    opsub,
    opmul,
    opdiv,
    opmod,
    // load from locals
    load,
    // load from captured
    loadc,
    // store to locals
    store,
    istore,
    // same but with operators like += and -=
    opstore,
    opistore,
    // return a value
    retval,
    // return no value
    retnone,
    // jump if true
    iftrue,
    // jump if false
    iffalse,
    // jump to index
    jump,
    // arg number
    argno
}

enum int[Opcode] opSizes = [
    // mat change: call, array, targeta, table, upcall
    Opcode.nop : 0, Opcode.push : 1, Opcode.pop : -1,
    Opcode.sub : 1, Opcode.bind : -1, Opcode.oplt : -1, Opcode.opgt : -1,
    Opcode.oplte : -1, Opcode.opgte : -1, Opcode.opeq : -1, Opcode.opneq : -1,
    Opcode.unpack : 1, Opcode.index : -1, Opcode.opneg : 0, Opcode.opadd : -1,
    Opcode.opsub : -1, Opcode.opmul : -1, Opcode.opdiv : -1, Opcode.opmod : -1,
    Opcode.load : 1, Opcode.loadc : 1, Opcode.store : -1, Opcode.istore : -3,
    Opcode.opistore : -3, Opcode.opstore: -1,
    Opcode.retval : 0, Opcode.retnone : 0, Opcode.iftrue : -1,
    Opcode.iffalse : -1, Opcode.jump : 0, Opcode.argno: 1,
];