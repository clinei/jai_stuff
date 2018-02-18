## Introduction

This is a description of a possible new feature for the [Jai programming language](https://www.youtube.com/watch?v=UTqZNujQOlA&list=PLmV5I2fxaiCKfxMBrNsU1kgKJXD3PkyxO&index=3), usage triggers. The feature would primarily be useful for large programs and libraries. It was written by a self-taught fan with no industry experience but a lot of experience using libraries with tons of friction. Someone with more experience working on large projects should check this for breaking edge cases and unacceptable loss of joy in programming.

That said, if [implemented](usage_triggers_impl.md), it can make documentation more integrated and dynamic, doing the right thing easier, and programming more enjoyable.

## Rationale

Most of us have used libraries which aren't always specific about their behavior or don't have good docs. I know I have. I've also seen bug reports caused by confusion about what a function or data structure does and how it should be used. I've also noticed that if something goes wrong, it usually takes me a while to find the part in the doc that tells me what I did wrong and how I should fix it.

So I thought, "What about having the library creator write code that tells me how to use things correctly when I get it wrong? That way, I could get the relevant part of the doc right when I need it, and not have to waste time searching for something that might not be there."

That seems to go right in line with the friction-reducing mentality of Jai.

So, we want to remove errors caused by not knowing how a certain API works, like trying to change a variable that should only be changed in certain ways or certain places, otherwise the API breaks. Restricting data access and usage patterns allows us to do that. However, we should not burden serious programmers who know what they're doing.

An example of a restriction we'd wanna implement is allowing a variable to be changed only in one place so we only have that place to look at when the variable somehow gets a wrong value. This concept is known as [data hiding](http://stevemcconnell.com/articles/missing-in-action-information-hiding/).

Restricting usage also allows us to disable valid but error-prone usages that we don't like so we can make programming bureaucratic again. However, if we're in a rush to push an important hotfix, it must be possible to disable such restrictions with ease. We can implement the restrictions with functions that get triggered when a specific thing is done, to allow or disallow it, which can be disabled by the user.

Since it must be possible to disable all restrictions from user code, all triggers must be public, and unless we wanna disable all of them or none, we need to be able to refer to them by name. Users of external code might want to add their own triggers to protect their own code from stupid mistakes, so we need the ability to add triggers to imported identifiers, outside the modules and declarations they were defined in.

While the average user wouldn't need this much control, library writers could use it to stop user bugs that experts would easily notice and avoid but novices would continuously step on, by letting the experts sign a short waiver, to be allowed to tinker with the internals. This specific method seems to work better than access modifiers at stopping new users from getting smashed around by your API or shooting themselves in the foot, because it allows you to give custom error messages for very specific usages, all of which can be disabled.

##### Conclusion

All triggers must be named, so they could be disabled selectively.

All triggers must refer to an identifier explicitly, so its usage could be validated thoroughly from any code that can use it.

All triggers must be public, so they could be disabled in client code.


## Method

We use new compiler directives `#trigger_ident`, `#trigger_decl`, and `#disable_trigger`.

Every time an identifier referenced in a `#trigger_ident` is used, the associated trigger function gets run.

Every time an identifier referenced in a `#trigger_decl` is used in a declaration, the statements the resulting identifier is used in will run the associated trigger function. More on this later.

A trigger function returns bool and takes as arguments a `*Code_Ident`, a `*Code_Node`, and a `*Code_Statement`, which can be used to allow or deny the usage of an identifier in specific kinds of expressions, in specific kinds of statements, and through the `*Code_Ident`, with specific kinds of declarations, like ones tagged with a specific `@note`. Returning `true` means the usage is allowed, returning `false` means it's not. 

`#disable_trigger` lets us -you guessed it- disable a trigger by name.

Trigger functions and boolean variables known at compile time can be combined using logical expressions, which will be turned into a trigger function returning the same logical combination with the functions turned into procedure calls under the hood.


## Syntax  (not final)

```
#trigger_ident <identifier> <name> :: <function>
```
`<identifier>` is any scope-visible declared identifier. Each time it is used in a statement, `<function>` gets called with the arguments being the `<identifier>`, the expression the identifier was found in, and the statement it was used in.

`<name>` is what the trigger can be referenced with in user code, a new public identifier. Can be called just like `<function>`.

`<function>` can be a named function, a `(*Code_Ident, *Code_Node, *Code_Statement) -> bool` lambda, or a logical expression of such lambdas. See [examples](#Examples).

```
#trigger_decl <identifier> <name> :: <function>
```
Same as above, except `<identifier>` must be an instantiable type, like struct, enum, enum_flags.

`<function>` is run when something declared with type `<identifier>` is used in a statement.

```
#disable_trigger <name> <name> ...
```
For the following statement or block, if names are provided, it disables the triggers that match those defined by a `#trigger_ident` or `#trigger_decl`. If `#disable_trigger` stands on its own, it disables all triggers.


## Examples

```
Foo :: true;
Bar :: false;

trigger_bar :: (ident : *Code_Ident, expr : *Code_Node, stmt : *Code_Statement) -> bool {

	return true;
}

Foozle :: struct {

	bar : int;
}
#trigger_ident Foozle.bar trigger_foozle_bar :: trigger_bar

Barzle :: struct {

	qux : float;
}
#trigger_ident Barzle.qux trigger_barzle_qux :: (Foo && Bar) || (trigger_foozle_bar)

Baz :: struct {

	foo : uint;
}
#trigger_decl Baz trigger_decl_baz :: false

Cov :: struct {

	Fe :: struct {

		fe : float;
	}

	fe : Fe;
}
#trigger_decl Cov trigger_decl_cov :: (ident : *Code_Ident, expr *Code_Node, stmt : *Code_Statement)
                                      //
                                      -> bool {
	return Bar;
}
#trigger_decl Cov.Fe trigger_decl_cov_fe :: (ident : *Code_Ident, expr *Code_Node, stmt : *Code_Statement)
                                            //
                                            -> bool {
	return Foo;
}

main :: () {

	baz : Baz;

	// runs `trigger_decl_baz` which fails
	//
	baz.foo += 1;

	foozle : Foozle;

	// runs `trigger_foozle_bar` which runs `trigger_bar` which succeeds
	//
	foozle.bar = 4;

	barzle : Barzle;

	// runs `trigger_barzle_qux` which runs `trigger_foozle_bar` which succeeds
	//
	barzle.qux = 2;

	cov : Cov;

	// disables `trigger_decl_cov` for the next statement, because it would fail
	//
	#disable_trigger trigger_decl_cov
	//
	// runs `trigger_decl_cov_fe` and succeeds
	//
	cov.fe.fe = 1.23;
}
```

A more specific and esoteric example: an API is so complex that in order to use it you have to read tons of docs. People who haven't read enough to use the API correctly but are confident that they have, will try to call functions and discover that they fail with the message "Read The Fucking Manual!". Taken aback, the user goes and reads the manual, greeted by a wizard that gives him the metal frame of an ancient `@note` and tells him to go find all the other bits scattered across the documentation. Only when he has collected all the pieces can he glue them together and tag his code with the correct `@note` and use the API. Or he can cheat and just use `#disable_trigger`. Oh well, his loss.

Or something more familiar: `#trigger_ident` can be used on function identifiers to say that they are deprecated and when they will be deleted, so the trigger runs when the user updates the library and compiles, and he'll know that his precious code paths are not long for this world.


## Considerations

Triggers will probably have to be processed before everything else. Or not. Hey, I'm not a compiler engineer. But I did try to [implement this using existing features](usage_triggers_impl.md).

`Code_Statement` will need a `.notes` member and `Code_Declaration` will need a `.statement` member. Maybe we also want notes on parameter declarations? Probably not.

This uses the same `Code_*` structures as the compiler message loop that lets us view code as it's compiled. We'll probably need more structs, like `Code_Trigger_Ident`, `Code_Trigger_Decl` and `Code_Disable_Trigger`.

I'm not quite sure how this dovetails with other language features, or any performance issues, but since this is a rather simple feature I don't see a way for something to break. But if you do find something that breaks, please create a GitHub issue and I'll be happy to read it.

If we could handle more useful cases with a simple addition or modification to the proposal, please create a GitHub issue as well.


## See also

1. http://stevemcconnell.com/articles/missing-in-action-information-hiding/

2. https://softwareengineering.stackexchange.com/questions/120019/whats-the-benefit-of-object-oriented-programming-over-procedural-programming/120038#120038 
(I don't fully agree with the guy, but he has some good points)

3. [A possible implementation using existing features](usage_triggers_impl.md)

4. The more involved code below

```
World :: struct {
	entities : [] Entity;

	times_guys_moved : uint = 0;

	#trigger_ident times_guys_moved
	//
	trigger_move_guy_world :: (ident : *Code_Ident, expr : *Code_Node, stmt : *Code_Statement) -> bool {

		// `ident` is the identifier that was in the statement that was triggered
		// in this case `times_guys_moved`

		// `expr` is the expression the identifier was found in
		// in this case `times_guys_moved += 1`

		// `stmt` is the statement the identifier was found in,
		// in this case `times_guys_moved += 1;` in procedure `move_guy`

		if the operation is not "+" or the right hand side is not literal "1" {

			printf("Error: The only operation allowed on `World.times_guys_moved` is `+= 1`");

			return true;
		}

		return false;
	}
}

// reminds users of `World` that it is not their plaything, every declaration of it is sent as `stmt`
//
#trigger_ident World trigger_great_responsibility_with_great_power ::
                     //
                     (ident : *Code_Ident, expr : *Code_Node, stmt : *Code_Statement)
                     //
                     -> bool {
	
	printf("This is just a warning");

	printf("With great power comes great responsibility");
	printf("Take good care of my World, ya hear?");

	return false;
}

// finds an entity inside an array by name and returns a pointer to it
//
search :: (world : *World, name : string) -> *Entity {}

vec2 :: struct {
	x : float;
	y : float;
}

Entity :: struct {

	using pos : vec2;

	// disallow mutating the position of any variable of this type outside `move_guy`
	//
	#trigger_ident pos.x trigger_pos_x :: !(!trigger_in_move_guy && trigger_mutate)
	//
	#trigger_ident pos.y trigger_pos_y :: trigger_pos_x

	// y positions can't be assigned directly, because I said so
	//
	#trigger_ident pos.y trigger_pos_y_no_assign :: !trigger_assign

	// note that you can still do `pos = ...`, like the sneak in the constructor of `Guy`,
	// that could be disabled with
	//
	// #trigger_ident pos trigger_pos :: !trigger_assign

	name : string;
}

// returns `false` when `ident` is in function `main`
//
trigger_in_main :: (ident : *Code_Ident, expr : *Code_Node, stmt : *Code_Statement)
                   //
                   -> bool {}

// returns `false` when `ident` is in function `move_guy`
//
trigger_in_move_guy :: (ident : *Code_Ident, expr : *Code_Node, stmt : *Code_Statement)
                       //
                       -> bool {}

// returns `false` when the statement is an assign
//
trigger_assign :: (ident : *Code_Ident, expr : *Code_Node, stmt : *Code_Statement)
                  //
                  -> bool {}

// returns `false` when the statement is an assign or other mutating operation on `ident`
//
trigger_mutate :: (ident : *Code_Ident, expr : *Code_Node, stmt : *Code_Statement)
                  //
                  -> bool {}

// returns `false` if `ident.declaration.statement.notes` includes @owner
//
trigger_owned :: (ident : *Code_Ident, expr : *Code_Node, stmt : *Code_Statement)
                 //
                 -> bool {}

@ComplexUsage
// returns `false` when the declaration of <parent> in `<parent>.<ident>` has an @owner note
//
trigger_parent_struct_owned :: (ident : *Code_Ident, expr : *Code_Node, stmt : *Code_Statement)
                               //
                               -> bool {

	parent : *Code_Ident;

	if expr.kind == DOT_EXPRESSION {

		for expr_ident : <idents in dot expression> {
			parent = expr_ident;

			if expr_ident == ident {
				break;
			}
		}

		return trigger_owned(parent, expr, stmt);
	}

	return false;
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
//
// @Speed
// This can be optimized into a #trigger_ident which checks only the declarations, but then the statement will
// be the declaration and the declaration will be the `Guy :: struct`, which won't work for our functions so far
//
#trigger_decl Guy trigger_guy_owned_in_main :: !( !trigger_in_main && trigger_owned )

// allow changing the `name` member of a variable of type `Guy` only when
// the variable is declared with an @owner note, like `@owner guy : Guy;`
/
#trigger_ident Guy.name trigger_guy_name :: trigger_mutate && trigger_parent_struct_owned

move_guy :: (using guy : *Guy, using world : World) {

	// runs `Entity.trigger_pos_x` which succeeds
	//
	x = 4;

	// the guy who wrote `Entity` is dumb!
	// why would you ever wanna not assign pos.y!?
	// who cares, I'm just gonna override it
	//
	#disable_trigger Entity.trigger_pos_y_no_assign
	//
	y = 2;

	// runs `World.trigger_move_guy_world` which succeeds
	//
	times_moved_guys += 1;
}

try_to_name_guy_but_fail :: (guy : *Guy, name : string) {

	// runs `trigger_guy_name` which fails
	// because the declaration of `guy` doesn't have an @owner note
	//
	guy.name = name;
}

save :: (target : *Guy, using savior : *Guy) {

	target.saved_by = name;
}
#trigger_ident save trigger_do_we_have_the_men :: false
//
#trigger_ident save trigger_are_we_likely_to_succeed :: false
//
#trigger_ident save trigger_is_consequentialism_better_than_deontology :: false

main :: () {

	// reminds us to take good care of this data structure
	world : World;

	// checks a single local identifier
	//
	#trigger_ident world trigger_world :: (ident : *Code_Ident, expr : *Code_Node, stmt : *Code_Statement)
                                          //
	                                      -> bool {
		return true;
	}

	// runs `trigger_guy_owned_in_main` which succeeds
	@owner
	guy : *Guy;

	try_to_name_guy_but_fail(guy, "Tom Hanks");

	// runs `trigger_guy_name` which
	// succeeds since the declaration is owned
	guy.name = "Tom Hanks";

	@owner
	guy2 : *Guy;
	guy2.name = "Private Ryan";

	// runs `trigger_world`
	move_guy(guy, world);

	// this guy is fuckin' nuts!
	#disable_trigger {
		private_ryan := cast(*Guy) search(&world, "Private Ryan");
		save(private_ryan, guy);
	}
}

```