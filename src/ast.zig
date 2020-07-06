const std = @import("std");
const Allocator = std.mem.Allocator;

const bog = @import("bog.zig");
const Token = bog.Token;
const TokenIndex = Token.Index;

pub const Tree = struct {
    tokens: []const Token,
    nodes: []const *Node,

    /// not owned by the tree
    source: []const u8,

    arena: std.heap.ArenaAllocator.State,
    gpa: *Allocator,

    pub fn deinit(self: *Tree) void {
        self.gpa.free(self.tokens);
        self.arena.promote(self.gpa).deinit();
    }

    pub const render = @import("render.zig").render;
};

pub const Node = struct {
    id: Id,

    pub const Id = enum {
        Decl,
        Fn,
        Discard,
        Identifier,
        This,
        Prefix,
        Infix,
        TypeInfix,
        Range,
        Suffix,
        Literal,
        Import,
        Error,
        Tagged,
        List,
        Tuple,
        Map,
        Block,
        Grouped,
        MapItem,
        Catch,
        If,
        For,
        While,
        Match,
        MatchCatchAll,
        MatchLet,
        MatchCase,
        Jump,
    };

    pub fn firstToken(node: *Node) TokenIndex {
        return switch (node.id) {
            .Decl => @fieldParentPtr(Node.Decl, "base", node).let_const,
            .Fn => @fieldParentPtr(Node.Fn, "base", node).fn_tok,
            .Identifier, .Discard, .This => @fieldParentPtr(Node.SingleToken, "base", node).tok,
            .Prefix => @fieldParentPtr(Node.Prefix, "base", node).tok,
            .Infix => @fieldParentPtr(Node.Infix, "base", node).lhs.firstToken(),
            .Range => {
                const range = @fieldParentPtr(Node.Range, "base", node);
                if (range.start) |some| return some.firstToken();
                return range.colon_1;
            },
            .TypeInfix => @fieldParentPtr(Node.TypeInfix, "base", node).lhs.firstToken(),
            .Suffix => @fieldParentPtr(Node.Suffix, "base", node).l_tok,
            .Literal => {
                const lit = @fieldParentPtr(Node.Literal, "base", node);
                return if (lit.kind != .none) lit.tok else lit.tok - 1;
            },
            .Import => @fieldParentPtr(Node.Import, "base", node).tok,
            .Error => @fieldParentPtr(Node.Error, "base", node).tok,
            .Tagged => @fieldParentPtr(Node.Tagged, "base", node).at,
            .List, .Tuple, .Map => @fieldParentPtr(Node.ListTupleMap, "base", node).l_tok,
            .Block => @fieldParentPtr(Node.Block, "base", node).stmts[0].firstToken(),
            .Grouped => @fieldParentPtr(Node.Grouped, "base", node).l_tok,
            .MapItem => {
                const map = @fieldParentPtr(Node.MapItem, "base", node);

                if (map.key) |some| return some.firstToken();
                return map.value.firstToken();
            },
            .Catch => @fieldParentPtr(Node.Catch, "base", node).lhs.firstToken(),
            .If => @fieldParentPtr(Node.If, "base", node).if_tok,
            .For => @fieldParentPtr(Node.For, "base", node).for_tok,
            .While => @fieldParentPtr(Node.While, "base", node).while_tok,
            .Match => @fieldParentPtr(Node.Match, "base", node).match_tok,
            .MatchCatchAll => @fieldParentPtr(Node.Jump, "base", node).tok,
            .MatchLet => @fieldParentPtr(Node.MatchLet, "base", node).let_const,
            .MatchCase => @fieldParentPtr(Node.MatchCase, "base", node).lhs[0].firstToken(),
            .Jump => @fieldParentPtr(Node.Jump, "base", node).tok,
        };
    }

    pub fn lastToken(node: *Node) TokenIndex {
        return switch (node.id) {
            .Decl => @fieldParentPtr(Node.Decl, "base", node).value.lastToken(),
            .Fn => @fieldParentPtr(Node.Fn, "base", node).body.lastToken(),
            .Identifier, .Discard, .This => @fieldParentPtr(Node.SingleToken, "base", node).tok,
            .Prefix => @fieldParentPtr(Node.Prefix, "base", node).rhs.lastToken(),
            .Infix => @fieldParentPtr(Node.Infix, "base", node).rhs.lastToken(),
            .TypeInfix => @fieldParentPtr(Node.TypeInfix, "base", node).type_tok,
            .Range => {
                const range = @fieldParentPtr(Node.Range, "base", node);
                if (range.step) |some| return some.firstToken();
                if (range.colon_2) |some| return some;
                if (range.end) |some| return some.firstToken();
                return range.colon_1;
            },
            .Suffix => @fieldParentPtr(Node.Suffix, "base", node).r_tok,
            .Literal => @fieldParentPtr(Node.Literal, "base", node).tok,
            .Import => @fieldParentPtr(Node.Import, "base", node).r_paren,
            .Error => {
                const err = @fieldParentPtr(Node.Error, "base", node);
                if (err.capture) |some| return some.lastToken();
                return err.tok;
            },
            .Tagged => {
                const tagged = @fieldParentPtr(Node.Tagged, "base", node);
                if (tagged.capture) |some| return some.lastToken();
                return tagged.name;
            },
            .List, .Tuple, .Map => @fieldParentPtr(Node.ListTupleMap, "base", node).r_tok,
            .Block => {
                const block = @fieldParentPtr(Node.Block, "base", node);
                return block.stmts[block.stmts.len - 1].lastToken();
            },
            .Grouped => @fieldParentPtr(Node.Grouped, "base", node).r_tok,
            .MapItem => @fieldParentPtr(Node.MapItem, "base", node).value.lastToken(),
            .Catch => @fieldParentPtr(Node.Catch, "base", node).rhs.lastToken(),
            .If => {
                const if_node = @fieldParentPtr(Node.If, "base", node);
                if (if_node.else_body) |some| return some.lastToken();
                return if_node.if_body.lastToken();
            },
            .For => @fieldParentPtr(Node.For, "base", node).body.lastToken(),
            .While => @fieldParentPtr(Node.While, "base", node).body.lastToken(),
            .Match => {
                const match = @fieldParentPtr(Node.Match, "base", node);
                return match.cases[match.cases.len - 1].lastToken();
            },
            .MatchCatchAll => @fieldParentPtr(Node.MatchCatchAll, "base", node).expr.lastToken(),
            .MatchLet => @fieldParentPtr(Node.MatchLet, "base", node).expr.lastToken(),
            .MatchCase => @fieldParentPtr(Node.MatchCase, "base", node).expr.lastToken(),
            .Jump => {
                const jump = @fieldParentPtr(Node.Jump, "base", node);
                switch (jump.op) {
                    .Return => |n| return if (n) |some| some.lastToken() else jump.tok,
                    .Break, .Continue => return jump.tok,
                }
            },
        };
    }

    pub const Decl = struct {
        base: Node = .{ .id = .Decl },
        capture: *Node,
        value: *Node,
        let_const: TokenIndex,
        eq_tok: TokenIndex,
    };

    pub const Fn = struct {
        base: Node = .{ .id = .Fn },
        params: []*Node,
        body: *Node,
        fn_tok: TokenIndex,
        r_paren: TokenIndex,
    };

    pub const SingleToken = struct {
        base: Node,
        tok: TokenIndex,
    };

    pub const Prefix = struct {
        base: Node = .{ .id = .Prefix },
        op: Op,
        tok: TokenIndex,
        rhs: *Node,

        pub const Op = enum {
            boolNot,
            bitNot,
            minus,
            plus,
            Try,
        };
    };

    pub const TypeInfix = struct {
        base: Node = .{ .id = .TypeInfix },
        op: enum {
            is,
            as,
        },
        lhs: *Node,
        tok: TokenIndex,
        type_tok: TokenIndex,
    };

    pub const Infix = struct {
        base: Node = .{ .id = .Infix },
        op: enum {
            BoolOr,
            BoolAnd,
            LessThan,
            LessThanEqual,
            GreaterThan,
            GreaterThanEqual,
            Equal,
            NotEqual,
            In,
            BitAnd,
            BitOr,
            BitXor,
            LShift,
            RShift,
            Add,
            Sub,
            Mul,
            Div,
            DivFloor,
            Mod,
            Pow,

            // assignment ops
            Assign,
            AddAssign,
            SubAssign,
            MulAssign,
            PowAssign,
            DivAssign,
            DivFloorAssign,
            ModAssign,
            LShiftAssign,
            RShiftAssign,
            BitAndAssign,
            BitOrAssign,
            BitXOrAssign,
        },
        tok: TokenIndex,
        lhs: *Node,
        rhs: *Node,
    };

    pub const Range = struct {
        base: Node = .{ .id = .Range },
        start: ?*Node,
        end: ?*Node,
        step: ?*Node,
        colon_1: TokenIndex,
        colon_2: ?TokenIndex,
    };

    pub const Suffix = struct {
        base: Node = .{ .id = .Suffix },
        lhs: *Node,
        op: union(enum) {
            call: []*Node,
            subscript: *Node,
            member,
        },
        l_tok: TokenIndex,
        r_tok: TokenIndex,
    };

    pub const Literal = struct {
        base: Node = .{ .id = .Literal },
        kind: enum {
            str,
            num,
            int,
            True,
            False,
            none,
        },
        tok: TokenIndex,
    };

    pub const Import = struct {
        base: Node = .{ .id = .Import },
        tok: TokenIndex,
        str_tok: TokenIndex,
        r_paren: TokenIndex,
    };

    pub const Error = struct {
        base: Node = .{ .id = .Error },
        tok: TokenIndex,
        capture: ?*Node,
    };

    pub const Tagged = struct {
        base: Node = .{ .id = .Tagged },
        at: TokenIndex,
        name: TokenIndex,
        capture: ?*Node,
    };

    pub const ListTupleMap = struct {
        base: Node,
        values: []*Node,
        l_tok: TokenIndex,
        r_tok: TokenIndex,
    };

    pub const Block = struct {
        base: Node,
        stmts: []*Node,
    };

    pub const Grouped = struct {
        base: Node = .{ .id = .Grouped },
        expr: *Node,
        l_tok: TokenIndex,
        r_tok: TokenIndex,
    };

    pub const MapItem = struct {
        base: Node = .{ .id = .MapItem },
        key: ?*Node,
        colon: ?TokenIndex,
        value: *Node,
    };

    pub const Catch = struct {
        base: Node = .{ .id = .Catch },
        tok: TokenIndex,
        lhs: *Node,
        capture: ?*Node,
        rhs: *Node,
        let_const: ?TokenIndex,
    };

    pub const If = struct {
        base: Node = .{ .id = .If },
        cond: *Node,
        if_body: *Node,
        else_body: ?*Node,
        capture: ?*Node,
        let_const: ?TokenIndex,
        eq_tok: ?TokenIndex,
        else_tok: ?TokenIndex,
        if_tok: TokenIndex,
        r_paren: TokenIndex,
    };

    pub const For = struct {
        base: Node = .{ .id = .For },
        capture: ?*Node,
        cond: *Node,
        body: *Node,
        let_const: ?TokenIndex,
        in_tok: ?TokenIndex,
        for_tok: TokenIndex,
        r_paren: TokenIndex,
    };

    pub const While = struct {
        base: Node = .{ .id = .While },
        cond: *Node,
        body: *Node,
        capture: ?*Node,
        let_const: ?TokenIndex,
        eq_tok: ?TokenIndex,
        while_tok: TokenIndex,
        r_paren: TokenIndex,
    };

    pub const Match = struct {
        base: Node = .{ .id = .Match },
        expr: *Node,
        cases: []*Node,
        match_tok: TokenIndex,
        r_paren: TokenIndex,
    };

    pub const MatchCatchAll = struct {
        base: Node = .{ .id = .MatchCatchAll },
        expr: *Node,
        tok: TokenIndex,
        eq_arr: TokenIndex,
    };

    pub const MatchLet = struct {
        base: Node = .{ .id = .MatchLet },
        capture: *Node,
        expr: *Node,
        let_const: TokenIndex,
        eq_arr: TokenIndex,
    };

    pub const MatchCase = struct {
        base: Node = .{ .id = .MatchCase },
        lhs: []*Node,
        expr: *Node,
        eq_arr: TokenIndex,
    };

    pub const Jump = struct {
        base: Node = .{ .id = .Jump },
        tok: TokenIndex,
        op: union(enum) {
            Break,
            Continue,
            Return: ?*Node,
        },
    };
};
