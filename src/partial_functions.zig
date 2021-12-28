const std = @import("std");
const print = std.debug.print;
const panic = std.debug.panic;
const expect = std.testing.expect;

fn freq(t: f32, f: f32, v: f32) f32 {
    return f / (t + 0.001 * v);
}

/// Transform a function of n arguments into a function of type FuncReturnT with
/// a single argument, fixing all other arguments according to partial_args,
/// except for one undefined value.
pub fn partialize(
    comptime func: anytype,
    comptime FuncReturnT: type,
    comptime partial_args: anytype,
) FuncReturnT {
    // TODO we could also partialize w/ several args, but not sure it is very important
    // TODO would be better to have partial_args not be a tuple but a real
    // struct with named fields, so that we could match these fields with
    // the names of arguments of the function. But we can't access the names
    // of the arguments function?
    const FuncT: type = @TypeOf(func);
    const ReturnT: type = @typeInfo(FuncT).Fn.return_type.?;
    const ArgsT: type = std.meta.ArgsTuple(FuncT);
    const PartialArgsT = @TypeOf(partial_args);
    const fieldsArgs = std.meta.fields(ArgsT);
    const fieldsPArgs = std.meta.fields(PartialArgsT);
    if (fieldsArgs.len != fieldsPArgs.len) {
        panic("Error: not the same number of arguments in func and args.", .{});
    }
    const MissingArgType = @typeInfo(FuncReturnT).Fn.args[0].arg_type.?;
    if (@typeInfo(FuncReturnT).Fn.args.len != 1) {
        panic("Error: the returned function should have a single argument.\n", .{});
    }
    return struct {
        fn apply(missing_arg: MissingArgType) ReturnT {
            var complete_args: ArgsT = undefined;
            // iterate over the fields to fill in complete_args
            var n_found_missing: u32 = 0;
            inline for (std.meta.fields(ArgsT)) |f, i| {
                // select field address to fill
                const field = &@field(complete_args, f.name);
                if (@typeInfo(fieldsPArgs[i].field_type) != std.builtin.TypeInfo.Undefined) {
                    // if not undefined, simply copy from partial_args
                    field.* = @field(partial_args, f.name);
                } else {
                    // if undefined, use missing_args
                    field.* = missing_arg;
                    n_found_missing += 1;
                    // print("Missing arg #{} set to {}\n", .{ i, missing_arg });
                }
            }
            if (n_found_missing == 0) {
                panic("No argument missing ('undefined' in partial_args).\n", .{});
            } else if (n_found_missing > 1) {
                panic("Too many arguments missing ('undefined' in partial_args).\n", .{});
            }
            return @call(.{ .modifier = .always_inline }, func, complete_args);
        }
    }.apply;
}

/// Given a type like fn (f32, i32, f32) f32, returns 
/// a tuple type {f32, i32, f32}
/// TODO remove! like std.meta.ArgsTuple!
// fn partial_args_type(FuncReturnT: T) type {
//     const missing_args = @typeInfo(FuncReturnT).Fn.args;
//     const missing_args_fields = [_]std.builtin.TypeInfo.StructField{} ** missing_args.len;
//     inline for (missing_args_fields) |ma, i| {
//         // ignore name, because is_tuple?
//         ma.field_type = missing_args[i].arg_type;
//     }
//     const info: std.builtin.TypeInfo = std.builtin.TypeInfo{
//         .Struct = .{
//             .layout = .Auto,
//             .fields = &missing_args_fields,
//             .decls = &[0]std.builtin.TypeInfo.Declaration{},
//             .is_tuple = true,
//         },
//     };
//     return @Type(info);
// }

/// Given a like: fn (f32, i32, f32) f32
/// returns: fn ({f32, i32, f32}) f32
/// where the sole argument of the function is a tuple
fn partial_func_type(comptime FuncReturnT: type) type {
    // const ArgsType = partial_args_type(FuncReturnT);
    const ArgsType = std.meta.ArgsTuple(FuncReturnT);
    const single_arg = std.builtin.TypeInfo.FnArg{
        .is_generic = false,
        .is_noalias = false,
        .arg_type = ArgsType,
    };
    const single_arg_array = [1]std.builtin.TypeInfo.FnArg{single_arg};
    return @Type(std.builtin.TypeInfo{
        .Fn = .{
            .calling_convention = .Unspecified,
            .alignment = 0,
            .is_generic = false,
            .is_var_args = false,
            .args = single_arg_array[0..],
            .return_type = @typeInfo(FuncReturnT).Fn.return_type.?,
        },
    });
}

// TODO broken, but I don't understand why.
pub fn partialize_nargs(
    comptime func: anytype,
    comptime FuncReturnT: type,
    comptime partial_args: anytype,
    comptime PFT: type,
    // ) partial_func_type(FuncReturnT) { //TODO restore that
) PFT {
    _ = FuncReturnT;
    const FuncT: type = @TypeOf(func);
    const ReturnT = @typeInfo(FuncT).Fn.return_type.?;
    const ArgsT: type = std.meta.ArgsTuple(FuncT);
    const PartialArgsT = @TypeOf(partial_args);
    const fieldsArgs = std.meta.fields(ArgsT);
    const fieldsPArgs = std.meta.fields(PartialArgsT);
    if (fieldsArgs.len != fieldsPArgs.len) {
        panic("Error: not the same number of arguments in func and args.", .{});
    }
    // compute type of argument of the partial function:
    // a tuple containing the right types, as specified in FuncReturnT
    // const MissingArgType = std.meta.ArgsTuple(partial_func_type(FuncReturnT));
    const MissingArgType = std.meta.ArgsTuple(PFT);

    return struct {
        fn apply(missing_arg: MissingArgType) ReturnT {
            var complete_args: ArgsT = undefined;
            // iterate over the fields to fill in complete_args
            comptime var n_found_missing: u32 = 0;
            inline for (std.meta.fields(ArgsT)) |f, i| {
                // select field address to fill
                const field = &@field(complete_args, f.name);
                if (@typeInfo(fieldsPArgs[i].field_type) != std.builtin.TypeInfo.Undefined) {
                    // if not undefined, simply copy from partial_args
                    field.* = @field(partial_args, f.name);
                } else {
                    // if undefined, use missing_args
                    // field.* = missing_arg[0][n_found_missing];
                    // field.* = missing_arg[n_found_missing];
                    field.* = 3.0;
                    _ = missing_arg;
                    // field.* = missing_arg.@"0".@"0";
                    n_found_missing += 1;
                    // print("Missing arg #{} set to {}\n", .{ i, missing_arg });
                }
            }
            if (n_found_missing == 0) {
                panic("No argument missing ('undefined' in partial_args).\n", .{});
            } else if (n_found_missing > 1) {
                panic("Too many arguments missing ('undefined' in partial_args).\n", .{});
            }
            return @call(.{ .modifier = .always_inline }, func, complete_args);
        }
    }.apply;
}

test "partial functions of 1 arg" {
    // test with 1st argument
    const partial_args = .{ undefined, 200.0, 0.5 };
    const partial = comptime partialize(freq, fn (f32) f32, partial_args);
    var i: f32 = 0.0;
    while (i < 100) : (i += 1) {
        try expect(partial(i) == freq(i, 200.0, 0.5));
    }
    // test with 2nd argument
    const partial_args2 = .{ 3.0, undefined, 0.4 };
    const partial2 = comptime partialize(freq, fn (f32) f32, partial_args2);
    i = 0.0;
    while (i < 100) : (i += 1) {
        try expect(partial2(i) == freq(3.0, i, 0.4));
    }
}

test "partial functions of several args" {
    // broken: ./src/partial_functions.zig:161:6: error: expected type 'fn(std.meta.struct:922:38) f32', found 'fn(std.meta.struct:922:38) f32'
    // const partial_args = .{ undefined, 200.0, undefined };
    // const TT = partial_func_type(fn (f32, f32) f32);
    // // _ = TT;
    // const partial = comptime partialize_nargs(freq, fn (f32, f32) f32, partial_args, TT);
    // var i: f32 = 0.0;
    // while (i < 100) : (i += 1) {
    //     try expect(partial(.{ i, i + 3 }) == freq(i, 200.0, i + 3));
    // }
    // const a = .{ 3.0, 2.0, 1.0 };
    // print("{}\n", .{a[1]});
}
