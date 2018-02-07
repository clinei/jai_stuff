/*

DISCLAIMER

This was written by a self-taught fan, based on code seen in the YouTube playlist,
who believes that the data access and usage validation aspect of OOP is salvageable
and useful, mostly for large projects and libraries.
Someone with more experience working on large projects should look this over and
check if this breaks in some edge case or makes programming much less enjoyable.


RATIONALE

Restricting data access and usage patterns allows us to remove errors caused by
not knowing how a certain API works, like trying to change a variable that
should only be changed in certain ways or certain places (like places where
the a pointer to that variable is marked by a special @note) or only by
functions in a specific namespace, whether injected by the user or part of
the library itself.

It also allows us to disable valid but error-prone usages that we don't like
so we can make programming bureaucratic again :^)

But fret not, all checks and balances can be disabled if you're in a rush to
push an important hotfix, optionally with surgical precision.

Jokes aside, while the average user wouldn't need this much control,
library writers could use it to stop user bugs that experts could easily notice
and avoid but novices would continuously step on, by letting the experts
sign a short waiver to tinker with the internals, and this specific method
seems to work way better at stopping new users from getting smashed around
by your API or shooting themselves in the foot, than access modifiers,
because it allows you to provide custom error messages for highly specific
usages, perhaps even defining the order in which someone should call functions,
by storing info about the checked statements in module-level global variables.

A more specific if also esoteric example:
an API is so complex that in order to use it you have to read tons of docs.
People who haven't read enough to use the API correctly but are confident
that they have, will try to call the functions and discover that they fail
with the message "Read The Fucking Manual!". Taken aback, the user goes and
reads the manual, getting greeted by a wizard that gives him a broken @note and
tells him to go find all the other bits scattered across the documentation.
Only when he has collected all the pieces can he glue them together and
tag his code with the correct @note and use the API.
Or he can cheat and just use #override_check. Oh well, his loss.

In conclusion:
All checks must be named, so they can be selectively overridden.
All checks must refer to an identifier explicitly, so they can be
tagged onto any type from any place that can use it, like user code
checking a library type because their purposes require stricter usage.
All checks must be public so that they can be overridden in client code.


METHOD

Every time something tagged with #check_ident is used, the associated validator is run.
Every time something tagged with #check_decl is used in a declaration, the statements in which
the resulting identifier is used in will run the validator.

A validator takes as arguments a `Code_Declaration` and a `Code_Statement` which
can be used to allow or deny the usage of a type or identifier in specific kinds of statements,
with a specific kind of declaration, like @notes on the declaration.

A validator returns a boolean variable that tells the compiler to stop if it's false, or continue.
Validators and boolean variables known at compile time can be combined using logical expressions,
which will be turned into a bool-returning lambda under the hood.

In the current example, `Code_Declaration` must have info about the scope and function it is in.


INTERACTIONS

This uses the same Code_* structures as the compiler message loop that lets us modify code
on the fly. We'll probably need Code_Check_Ident, Code_Check_Decl and Code_Override_Check structs
that get sent to the message loop.

I'm not quite sure how this dovetails with other language features, or any performance issues, but
since the checks are public and use regular functions and identifiers which are simple language features,
I don't see how anything could break, but if you find something that does then please create a GitHub issue
and I'll be happy to read it.


SYNTAX

```
#check_ident <identifier> <name> :: <validator>
```
<identifier> is the target of the check, any scope-visible declared identifier
<name> is the name that can be referenced in user code, a new public identifier
<validator> can be a `(decl, stmt) -> bool` lambda, a named function, or
a logical expression which is turned into a bool-returning lambda and which
can do logical operations on bool-returning functions.

```
#check_decl <identifier> <name> :: <validator>
```
same as above, except
<identifier> must be an instantiable type, like struct, enum, enum_flags

```
#override_check <name> <name> ...
```
input is array of names.
For the following statement or block,
if names are provided, it disables each check that
matches those defined by #check_ident or #check_decl
if not, it disables all checks.


EXAMPLES
```
Foo :: true;
Bar :: false;

check_bar :: (decl : Code_Declaration, stmt : Code_Statement) -> bool {
	return true;
}

Foozle :: struct {
	bar : int;
}
#check_ident Foozle.bar check_foozle_bar :: check_bar

Barzle :: struct {
	qux : float;
}
#check_ident Barzle.qux check_barzle_qux :: (Foo && Bar) || (check_foozle_bar)

Baz :: struct {
	foo : uint;
}
#check_decl Baz check_decl_baz :: false

Cov :: struct {
	Fe :: struct {
		fe : float;
	}

	fe : Fe;
}
#check_decl Cov check_decl_cov :: (decl : Code_Declaration, stmt : Code_Statement) -> bool { return Bar; }
#check_decl Cov.Fe check_decl_cov_fe :: (decl : Code_Declaration, stmt : Code_Statement) -> bool { return Foo; }

main :: () {
	baz : Baz;

	// runs `check_decl_baz` and fails
	baz.foo += 1;

	foozle : Foozle;

	// runs `check_foozle_bar` which runs `check_bar` which succeeds
	foozle.bar = 4;

	barzle : Barzle;

	// runs `check_barzle_qux` which runs `check_foozle_bar` which succeeds
	barzle.qux = 2;

	cov : Cov;

	// disables `check_decl_cov` for the next statement, because it would fail
	#override_check check_decl_cov

	// runs `check_decl_cov_fe` and succeeds
	cov.fe.fe = 1.23;
}

```


SEE ALSO

1. https://softwareengineering.stackexchange.com/questions/120019/whats-the-benefit-of-object-oriented-programming-over-procedural-programming/120038#120038

2. The more involved code below

*/


World :: struct {
	entities : []Entity;

	times_guys_moved : uint = 0;

	// use a quick lambda to say that the only operation allowed on this data member is `+= 1`
	#check_ident times_guys_moved
	check_move_guy_world :: (decl : Code_Declaration, stmt : Code_Statement) -> bool {

		// `decl` is the declaration this check is attached to,
		// in this case `times_guys_moved : uint = 0`

		// `stmt` is the statement that tries to use the identifier in `decl`,
		// in this case `times_guys_moved += 1` in function `move_guy`

		// return true if right side is literal "1" and operation is "+"
	}
}

// finds an entity inside an array by name and returns a pointer to it
search :: (entities : []Entity, name : string) -> *Entity {}

vec2 :: struct {
	x : float;
	y : float;
}

Entity :: struct {
	using pos : vec2;

	// disallow mutating the position of any variable of this type outside `move_guy`
	#check_ident pos.x check_pos_x :: !(!check_in_move_guy && check_mutate)
	#check_ident pos.y check_pos_y :: check_pos_x

	// y positions can't be assigned directly, because I said so
	#check_ident pos.y check_pos_y_no_assign :: !check_assign

	// note that you can still do `pos = ...`, like the sneak in the constructor of `Guy`,
	// that could be disabled with
	// #check_ident pos check_pos :: !check_assign

	name : string;
}

// returns `true` if `decl` is in function `main`
check_in_main :: (decl : Code_Declaration, stmt : Code_Statement) -> bool {}

// returns `true` if `decl` is in function `move_guy`
check_in_move_guy :: (decl : Code_Declaration, stmt : Code_Statement) -> bool {}

// returns `true` when the statement is an assign
check_assign :: (decl : Code_Declaration, stmt : Code_Statement) -> bool {}

// returns `true` if the statement tries to assign or do a mutating operation on the identifier in `decl`
check_mutate :: (decl : Code_Declaration, stmt : Code_Statement) -> bool {}

// returns `true` if the type in the declaration is marked by the @owner note
check_owned :: (decl : Code_Declaration, stmt : Code_Statement) -> bool {}

// returns `true` if the type in the declaration of the parent identifier of the one used in the statement
// is an owned pointer
// @ComplexUsage
check_parent_struct_owned :: (decl : Code_Declaration, stmt : Code_Statement) -> bool {
	// get the ident in the declaration
	ident : Code_Ident = decl.identifier;

	// the parent
	parent : Code_Ident;

	// walk down the left side of the statement until the name of the current ident
	// matches the one in the declaration and then break, setting `parent` at the end of the loop and
	// breaking in the middle
	// if ident is `ident` and `stmt` is `get.the.parent.ident = 2;` then the parent is `parent`

	// return whether the declaration of `parent` contains an @owner note
}

Guy :: struct {
	using base : Entity;

	#constructor (guy : *Guy) {
		guy.name = "Soldier";
		guy.pos = vec2(3.14, 3.60);
	}

	saved_by : string;
}

// disallow ownership of variables of type `Guy` in functions other than `main`
// @Speed
// This can be optimized into a #check_ident which checks only the declarations, but then the statement will
// be the declaration and the declaration will the `Guy :: struct`, which won't work for our functions so far
#check_decl Guy check_guy_owned_in_main :: !(!check_in_main && check_owned)

// allow changing the `name` member of a variable of type `Guy` only when the variable is declared with an @owner note
// @OutsideStruct
#check_ident Guy.name check_guy_name :: check_mutate && check_parent_struct_owned

move_guy :: (using guy : *Guy, using world : World) {
	// runs `Entity.check_pos_x` which succeeds
	x = 4;

	// the guy who wrote `Entity` is dumb!
	// why would you ever wanna not assign pos.y!?
	// who cares, I'm just gonna override it
	#override_check Entity.check_pos_y_no_assign
	y = 2;

	// runs `World.check_move_guy_world` which succeeds
	times_moved_guys += 1;
}

try_to_name_guy_but_fail :: (guy : *Guy, name : string) {
	// runs `check_guy_name` with the first argument as the declaration and
	// the assign as the statement, which fails because the statement tries to mutate a 
	// member variable but the declaration is a non-owned pointer to `Guy`
	guy.name = name;
}

save :: (target : *Guy, using savior : *Guy) {
	target.saved_by = name;
}

#check_ident save check_do_we_have_the_men :: false
#check_ident save check_are_we_likely_to_succeed :: false
#check_ident save check_is_deontology_better_than_consequentialism :: false

main :: () {
	world : World;

	// checks a single identifier
	// @SingleVariable
	// @UserCode
	#check_ident world check_world :: (decl : Code_Declaration, stmt : Code_Statement) -> bool {
		return true;
	}

	// runs `check_guy_owned_in_main` which succeeds
	@owner
	guy : *Guy;

	try_to_name_guy_but_fail(guy, "Tom Hanks");

	// runs `check_guy_name` which
	// succeeds since the declaration is owned
	guy.name = "Tom Hanks";

	@owner
	guy2 : *Guy;
	guy2.name = "Private Ryan";

	move_guy(guy, world);

	// this guy is fuckin' nuts!
	#override_check {
		private_ryan := cast(*Guy) search(world.entities, "Private Ryan");
		save(private_ryan, guy);
	}
}
