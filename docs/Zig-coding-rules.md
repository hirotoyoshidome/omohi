# Zig Coding Rules

This document defines coding rules for Zig and also serves as a guideline for AI agents to implement with Zig-like design.
The goal is not merely "working code," but the continuous production of explicit, maintainable, reviewable code that is fit for OSS publication.

## Scope
* Target language: Zig
* Target version: `0.15.2` (fixed)
* Target code: application code / library code / `build.zig` / test code
* Priority order of this document
  * 1) Safety and explicitness
  * 2) Clarity of ownership and lifetime
  * 3) Zig-like low-cost abstractions
  * 4) Ease of implementation (ease of writing for AI)

## Assumptions of This Document (Understanding Zig)
* There is no GC
* There are no exceptions (use `error union (!T)`)
* There are no classes / interfaces / traits / inheritance
* The package system is not central (modules are file-based, dependency management is done in `build.zig`)
* Assume `std` evolves quickly, so use it with a fixed version
* External libraries should generally not be used (if an exception is made, document the reason for adoption, update policy, and reproducibility)

## Goals (Design Quality Criteria)
* Ownership, lifetime, and failure behavior should be understandable just by reading the code
* Behavior should be inferable locally (do not create hidden side effects)
* Express statically anything that can be expressed at comptime rather than runtime
* Introduce abstractions only when necessary and avoid over-abstraction
* Make dependency, memory, and error boundaries explicit in the code

## Most Important Principles (Zig-Like Design)
* Prioritize explicitness
  * Avoid implicit conversions, hidden allocations, and hidden ownership transfer
* Decide ownership first
  * Decide borrowed / owned / arena-managed before writing the API
* Decide the data model before the abstraction
  * First solidify `struct` / `enum` / `union(enum)`
* Prefer static design over runtime polymorphism
  * Consider `comptime` / `anytype` / `type` / `union(enum)` first
* Allow danger only at boundaries
  * Confine `@ptrCast`, `*anyopaque`, and C compatibility to boundaries

## AI Agent Implementation Rules (Required)
When AI implements Zig, it must decide at least the following before writing code.

* 1. Ownership
  * Whether the return value is borrowed / owned / arena-managed
* 2. Lifetime
  * What the return value's validity depends on (arguments / allocator / arena / static)
* 3. Error policy
  * Whether to propagate with `try`, or convert/substitute with `catch`
* 4. Allocator policy
  * Whether it is injected as an argument, managed by the caller, or handled by a local arena
* 5. Abstraction policy
  * Whether to use static DI / tagged union / dynamic DI (exception only)
* 6. Public boundary
  * The minimal API to make `pub`, and the boundary that hides internal implementation

AI must not do the following.
* Return `[]u8` / `[]const u8` while ownership is still ambiguous
* Use `anyerror` casually
* Introduce a `vtable` with an unclear abstraction purpose
* Swallow failures with `catch` and treat them as success
* Create `init` / `deinit` mismatches where deallocation responsibility cannot be understood

## Design Process (Recommended Order)
1. Decide the data model (`struct` / `enum` / `union(enum)`)
2. Decide ownership and lifetime (borrowed / owned / arena-managed)
3. Decide the error boundary (propagation / conversion / fallback)
4. Decide where to inject the allocator
5. Decide the kind of abstraction (static DI as the first candidate)
6. Minimize the `pub` API
7. Write tests (success cases / failure cases / deallocation responsibility)

## API Design Rules
* Make the ownership and lifetime of return values explicit in the function name or doc comment
* Do not return a pointer if returning by value is sufficient
* Keep `pub` minimal (public API only)
* Avoid implicit memory allocation in `pub` APIs
  * If allocation is needed, take an allocator as an argument
* Use different return-value representations appropriately
  * `T`: cannot fail, no ownership transfer (or value copy)
  * `!T`: can fail
  * `?T`: absence of value is a normal case
  * Use complex representations such as `!?T` / equivalent to `? !T` only after strictly confirming necessity
* If using an out-parameter, make the purpose clear: "shifting allocation responsibility to the caller"
* Returning ownership types that encapsulate an allocator (for example, variable-length buffer types) tends to blur responsibility
  * Avoid this in principle; if returned, make deallocation responsibility explicit in docs and tests

## Public API Documentation Conventions (OSS Quality)
Doc comments are required for `pub` types / functions / constants.

Function docs must include at least the following.
* Summary (one line)
* Memory: `borrowed` / `owned` / `arena-managed`
* Lifetime: how long the return value remains valid
* Errors: errors that may occur (representative ones)
* Caller responsibilities: responsibility for `free` / `destroy` / `deinit`

Add the following as needed.
* Thread-safety
* Panics / traps (when invariants are violated)
* Complexity (when processing is heavy or involves linear scans)
* Even if not `pub`, short comments are recommended for internal functions at unsafe boundaries, ownership transfers, and FFI boundaries

## Naming Conventions (Readable Zig Style)
* Type names (`struct` / `enum` / `union` / `error set`): `PascalCase`
* Functions: `camelCase`
* Variables, fields, and constants: `snake_case`
  * Variables that hold types or functions should also consistently use `snake_case`
* Namespaces (file names and directory names): `snake_case`
* Error set names: context-revealing names (for example, `ParseError`, `StoreError`)
* Functions returning `bool` should be predicates (for example, `isValid`, `hasNext`)
* Function names that change ownership should express intent
  * For example: `dupeXxx`, `cloneXxx`, `takeOwned`, `intoOwned`
* Align lifecycle functions
  * `init` / `deinit`
  * If needed, `initCapacity`, `reset`, `clearRetainingCapacity`
* Follow the official style guide: https://ziglang.org/documentation/0.15.2/#Style-Guide

## Type Design Rules
* Choose signed / unsigned strictly based on purpose
* Limit `usize` to sizes, indexes, and pointer-size-aligned purposes
* Do not overuse `usize` for domain values (choose an appropriate integer type for values with meaning, such as IDs or counts)
* Resolve literal `comptime_int` / `comptime_float` to concrete types at boundaries
* Add intent to meaningful integers with type aliases
  * For example: `const UserId = u64;`
* Use `enum` proactively to represent states and categories
* Use `union(enum)` as the first choice for mutually exclusive states

## Union / Tagged Union Rules
* Use `union(enum)` by default
  * Because it can express state exclusivity and branching safety in the type system
* A bare `union` is allowed only when:
  * low-level representation optimization is required
  * external format / ABI compatibility is required
  * state management is guaranteed by another mechanism and the reason can be explained
* When using a bare `union`, document the following in docs:
  * which state is valid
  * responsibility for state transitions
  * how invalid states are prevented

## Pointer, Slice, and String Rules
* Consider slices `[]T` / `[]const T` first
* Use `*T` when "a single element must be updated"
* Prefer `*const T`, and make it mutable only when minimally necessary
* `?*T` is prohibited in principle (do not use it in normal business logic)
  * Alternatives: consider `?T` / `?Index` / `union(enum)`
* Do not use `[*]T` or `[*:0]T` outside C compatibility boundaries
* Treat Zig as having no character type
  * Use `[]const u8` as the default representation for strings
  * If a character encoding assumption exists (such as UTF-8), document it explicitly
* Use sentinels only when C API compatibility or format requirements demand them

## `self` Conventions (Method Design)
* Default to `self: *Self`
* Use `self: *const Self` for read-only access
* Allow pass-by-value only for small, immutable value types
* Do not use pass-by-value for operations that mutate state (the intent becomes ambiguous)

## Memory Management Rules (Required)
* Accept `std.mem.Allocator` as an argument
* Once allocation occurs, write the `defer` / `errdefer` plan in the same scope
* Types that own resources must provide `deinit`
* `deinit` should not generally be assumed to be idempotent
  * If double `deinit` should be safe, make that design explicit
* Do not confuse `alloc/free` with `create/destroy`
* Guarantee caller-side deallocation responsibility through docs and tests

### Ownership Categories (Must Be Classified into One)
* `borrowed`
  * Depends on the lifetime of the caller / arguments / static storage
* `owned`
  * Allocated inside the function, with deallocation responsibility held by the caller
* `arena-managed`
  * Allocated under an arena and released in bulk by the arena's `deinit`

### Arena Usage Rules
* Limit use to short-lived, high-volume allocation, bulk-free scenarios
* Do not use for long-lived data or caches
* Do not let values allocated under an arena outlive the arena
* If a return value is arena-managed, state that explicitly in docs

### Allocator Selection Rules
* Decision criteria: lifetime / ownership / performance / size limit / thread safety / FFI boundary
* Recommended usage
  * Temporary CLI data: `std.heap.ArenaAllocator`
  * General-purpose: `std.heap.GeneralPurposeAllocator`
  * High-speed fixed-size processing: `std.heap.FixedBufferAllocator`
  * FFI boundaries: `std.heap.c_allocator` (limited to boundaries)
* Limit `std.heap.page_allocator` to tests, validation, and simple use cases
* Allocator wrappers or decorators are useful for observation and validation
  * Because they increase responsibility and cost, leave the purpose in comments or docs when introducing them
* Leave reasons for exceptional selections in comments or docs

## Error Handling Rules
* Since exceptions are unavailable, treat `error union` as part of design
* `anyerror` is prohibited in principle (except when unavoidable at boundaries)
* Convert errors at domain boundaries
  * Do not leak low-level I/O errors too directly into upper domains
* Apply consistent criteria for choosing between `try` and `catch`
* Prefer meaningful error sets at public boundaries
  * Do not leak internal details as-is; convert them at the necessary level of granularity

### Cases for Using `try`
* It is acceptable to leave the decision to the caller
* This layer does not change the meaning
* Recovery is not this layer's responsibility

### Cases for Using `catch`
* You can fall back to an alternative value (and it is valid by spec)
* You convert the error into a domain error
* You rethrow after cleanup or observation

### Prohibited Practices (Error Handling)
* Silent swallowing with `catch`
* Continuing when recovery is impossible
* Forgetting cleanup on failure (not writing `errdefer` when you could)

### Distinguishing panic / trap
* `@panic`: for invariant violations or near-unreachable cases where diagnostic information should remain
* `@trap`: when immediate termination is appropriate and stopping is more important than diagnostics
* Normal I/O or validation failures must not panic (return `error`)

## comptime, Generics, and Builtins
* Use `comptime` where it makes design explicit
  * Static DI
  * Type constraints
  * Constant table generation
  * Type generation
* `anytype` is convenient, but do not leave it unconstrained
  * If needed, constrain it with `@TypeOf`, `@hasDecl`, `@hasField`, `@typeInfo`
  * On constraint violations, emit a clear message with `@compileError`
* Do not overuse comptime to create unreadable metaprograms
  * If runtime code is sufficient, write normal code
* Do not use `usingnamespace` in principle
  * Because name resolution becomes harder to trace; even when making an exception, keep the impact localized
* Use builtins at design-critical boundaries
  * For example: `@sizeOf`, `@alignOf`, `@typeInfo`, `@bitCast`
* Treat dangerous builtins as audit targets
  * For example: `@ptrCast`, `@intToPtr`, `@ptrToInt`
  * When used exceptionally, leave the reason, validity conditions, and ownership/deallocation responsibility in comments or docs

## Abstraction Rules (DI / Polymorphism)
* First choice: static DI (`comptime`, `anytype`, type parameters)
* If runtime selection is needed, consider `union(enum)` + `switch` first
  * It is type-safe and easy to trace
* Dynamic DI (`vtable` / `*anyopaque`) is prohibited in principle
  * Exception: plugin / dynamic loading / fixed ABI / when unknown implementations must be handled at runtime

### Conditions for Allowing Dynamic DI (Exceptions)
* You can explain why static DI or tagged union cannot satisfy the requirements
* Ownership / lifetime / `deinit` responsibility is made explicit
* Uses of `@ptrCast` are confined to boundaries
* `*anyopaque` is limited to vtable boundaries only
* Tests confirm at least the following
  * success case
  * `deinit` responsibility
  * assumptions that prevent lifetime violations

## C Compatibility and FFI Rules (Prohibited in Principle, Exceptions Only)
* Do not design around C compatibility by default
* Use `extern struct`, `packed struct`, and C-pointer forms only in exceptional cases
* At C boundaries, explicitly state the following
  * ownership (which side frees)
  * string termination convention (whether there is a sentinel)
  * alignment assumptions
  * thread safety
* Do not let C-derived unsafety spread into internal logic

## Module Structure Rules
* Separate responsibilities by file (roughly one file, one responsibility)
* Make the `pub` API the entry point and keep internal implementation private
* Keep dependency direction one-way (higher layers use lower layers)
* Do not leak `build.zig` dependency constraints into the business-logic layer

## `build.zig` / Dependency Management Rules
* Fix the Zig version (`0.15.2`)
* Localize APIs that are likely to be affected by changes in `std`
  * Do not scatter calls; confine them to thin internal wrappers or boundary functions
* External libraries should generally not be adopted
* If adopted as an exception, always document:
  * reason for adoption (comparison against in-house implementation / other OSS)
  * update policy (who follows updates and when)
  * response policy for breaking changes
  * how lock/reproducibility is ensured

## Coding Style
* Split functions by single responsibility
* Use `snake_case` for variable names, with lengths that are not too short and still convey meaning
* Use `if` / `switch` as expressions and make branch results explicit
* Design `switch` for exhaustiveness (welcome designs that break when a new state is added)
* Turn magic numbers into meaningful constants
* Perform casts at boundaries and state the reason
* Before mixing signed and unsigned values, decide which is appropriate for the domain
* Make integer rounding rules explicit with builtins, especially for division
  * For signed integer division, do not rely on `/`; choose what matches intent such as `@divTrunc`

## Testing Rules (OSS Publication Quality)
* Assume Zig's `test` feature
* Use `zig test` for single-file verification and `zig build test` for full verification
* Minimum test perspectives
  * success cases
  * failure cases (expected errors)
  * boundary values
  * ownership / deallocation responsibility (whether it leaks)
* For code that uses allocators, exercise deallocation paths in tests as well
* Dynamic DI / FFI / unsafe boundaries must have unit tests

## Review Checklist (Shared by AI and Humans)
* Is ownership readable?
* Do lifetime docs and implementation match?
* Is allocator responsibility consistent?
* Is `errdefer` placed correctly?
* Is `pub` not excessive?
* Does `anytype` have the necessary constraints?
* Are `@ptrCast` / `*anyopaque` confined to boundaries?
* Is failure not swallowed by `catch`?
* Is anything that could be represented with a tagged union unnecessarily made unsafe?

## Prohibited Items (Explicit)
* Returning a reference/pointer to a local variable that goes out of scope
* Returning an ownership type with ambiguous deallocation responsibility
* Overusing `?*T` in normal logic
* Using `@ptrCast`, `*anyopaque`, or C pointers without reason
* Habitual use of `anyerror`
* Silent error swallowing through `catch`
* Abstraction for abstraction's sake (introducing a vtable without real need)

## Implementation Template (Recommended)
```zig
/// Creates a User.
/// Memory: owned
/// Lifetime: caller manages until `destroyUser` (or equivalent deinit)
/// Errors: error{OutOfMemory}
/// Caller responsibilities: destroy returned pointer and free owned fields
pub fn createUser(allocator: std.mem.Allocator, name: []const u8) !*User {
    var user = try allocator.create(User);
    errdefer allocator.destroy(user);

    const owned_name = try allocator.dupe(u8, name);
    errdefer allocator.free(owned_name);

    user.* = .{
        .name = owned_name,
    };
    return user;
}
```

## Supplement (Criteria for Judging Zig-Likeness)
You may judge a design as "Zig-like" when the following are true.

* Ownership and lifetime can be traced through types / arguments / docs
* `comptime` is used appropriately without increasing runtime complexity
* Abstractions are low-cost and do not reduce debuggability
* Unsafe code is isolated at boundaries
* Tests verify failure paths and deallocation responsibility as well
