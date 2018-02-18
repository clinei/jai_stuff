Here's an implementation of [usage triggers](usage_triggers.md) using already existing features, namely notes and the compiler message loop.

For this to work, we need to add a `.notes` member to `Code_Statement`, and notes need to be parsed like procedure calls. That would also let us add comments like `@Speed("x64")` and `@Audit(assigned_to = "clinei,josh", priority = 2)` to any statement to be used by static analysis tools to send signals and automate development.

We also need to add a `.statement` member to `Code_Declaration`, so we can get `ident.declaration.statement.notes`.

Not implemented yet: triggers on members like `pos.x` or base types included with `using`, because we need to intercept the compiler while it's parsing to build a map.

I don't know how member access is represented yet, that would be helpful. I also don't know if the `*Code_Ident`s are the same in the statements and the declarations (the code assumes they are). A recent `Compiler.jai` would be very useful.

Compared to the [earlier proposal](usage_triggers.md) using compiler directives, adding triggers to imported idents requires aliasing them and adding the notes to the new declaration, like `@trigger(proc) my_struct :: imported_struct`. We also use structs for passing arguments and returning `null` means the same as returning a `Trigger_Response` with `.allowed = true`.

We can also use this to implement [pluggable type systems](http://bracha.org/pluggableTypesPosition.pdf).

We can implement `#deprecated` and `#check_call` using this, as well.

We can make the triggers propose code modifications, too.

The actual implementation is at the bottom of the file, and mostly in pseudocode.

```
@trigger(please_be_gentle)
//
World :: struct {

	entities : [] Entity;

	@trigger(trigger_guys_moved)
	//
	times_guys_moved : uint = 0;
}
please_be_gentle :: (data : *Trigger_Data) -> *Trigger_Response {

	response : *Trigger_Response = <get memory somehow>;

	response.text = concat("Take good care of my ", data.ident.name, ", ya hear?");

	response.text = concat(response.text, "\nThis is just a warning");

	response.text = concat(response.text, "\nWith great power comes great responsibility");

	return response;
}
trigger_guys_moved :: (data : *Trigger_Data) -> *Trigger_Response {

	// `data.ident` is the identifier that the declaration of which was
	// tagged with a note that points to this procedure
	//
	// in this case `times_guys_moved`

	// `data.expr` is the expression the identifier was found in
	//
	// in this case `times_guys_moved += 1`

	// `data.stmt` is the statement the identifier was found in
	//
	// in this case `times_guys_moved += 1;` in procedure `move_guy`


	response : *Trigger_Response = <get memory somehow>;   // maybe from a free list?

	if the operation is not "+" or the right hand side is not literal "1" {

		response.allowed = false;
		response.text = "The only operation allowed on `World.times_guys_moved` is `+= 1`.";
	}

	return response;
}

// finds an entity inside an array by name and returns a pointer to it
//
search :: (world : *World, name : string)
          //
          -> *Entity {}

vec2 :: struct {

	x : float;
	y : float;
}

// disallow mutating the x position of any variable of this type outside `move_guy`
//
@trigger_member( pos.x, "trigger_pos_x :: !( !trigger_in_move_guy && trigger_mutate )" )
//
// same for the y coordinate
// members of members with `using` can be referred to directly
//
@trigger_member( y, "trigger_pos_y :: trigger_pos_x" )
//
// y positions can't be assigned directly, because I said so
//
@trigger_member( pos.y, "trigger_pos_y_no_assign :: !trigger_assign")
//
// note that you can still do `pos = ...`, like the sneak in the constructor of `Guy`,
// that could be disabled with
// @trigger_member( pos, "trigger_pos :: !trigger_assign" )
//
Entity :: struct {

	using pos : vec2;

	name : string;
}

// allows when if `ident` is in function `main`
//
trigger_in_main :: (data : *Trigger_Data)
                   //
                   -> *Trigger_Response {}

// allows when `ident` is in function `move_guy`
//
trigger_in_move_guy :: (data : *Trigger_Data)
                       //
                       -> *Trigger_Response {}

// allows when the left side of the statement is an assign
//
trigger_assign :: (data : *Trigger_Data)
                  //
                  -> *Trigger_Response {}

// allows when the statement assigns or does a mutating operation on `ident`
//
trigger_mutate :: (data : *Trigger_Data)
                  //
                  -> *Trigger_Response {}

// allows when `ident.declaration.statement` is marked with an @owner note
//
trigger_owned :: (data : *Trigger_Data)
                 //
                 -> *Trigger_Response {}

@ComplexUsage
//
// allows when the declaration of <parent> in `<parent>.<ident>` has an @owner note
//
trigger_parent_struct_owned :: (data : *Trigger_Data)
                               //
                               -> *Trigger_Response {
	parent : *Code_Ident;

	// we wouldn't need to copy if we used *Code_Ident, *Code_Node, *Code_Statement as arguments
	//
	data_copy : *Trigger_Data;

	memcpy( data_copy, data, sizeof(Trigger_Data) );

	if data.expr.kind == DOT_EXPRESSION {

		for expr_ident : <idents in dot expression> {
			parent = expr_ident;

			if expr_ident == ident {
				break;
			}
		}

		data_copy.ident = parent;

		return trigger_owned(data_copy);
	}

	return null;
}

// disallow @owner notes on declaration statements with type `Guy` in functions other than `main`
//
@trigger( trigger_guy_owned_in_main )
//
// allow changing the `name` member of a variable of type `Guy` only when
// the variable is declared with an @owner note, like `@owner guy : Guy;`
//
@trigger_member( name, "trigger_guy_name :: trigger_mutate && trigger_parent_struct_owned" )
//
Guy :: struct {

	using base : Entity;

	#constructor (guy : *Guy) {
		guy.name = "Soldier";
		guy.pos = vec2(3.14, 3.60);
	}

	saved_by : string;
}
//
@ComplexUsage
//
// adapts existing procedures that work on statements to work on declarations
//
trigger_guy_owned_in_main :: (data : *Trigger_Data)
                             -> *Trigger_Response {

	@Audit("is this the ident expression?", assigned_to = "abnercoimbre")
	//
	ident := cast(*Code_Ident) data.stmt.expressions[0];

	expr := data.stmt.base;

	main :: trigger_in_main(ident, expr, stmt);

	owned :: trigger_owned(ident, expr, stmt);


	response : *Trigger_Response = <get memory somehow>;

	response.allowed = !( !main.allowed && owned.allowed );

	// see also :Expanded

	return response;
}

move_guy :: (using guy : *Guy, using world : World) {

	// runs `trigger_pos_x` which succeeds
	//
	x = 4;

	// the guy who wrote the trigger on `Entity` is dumb!
	// why would you ever wanna not assign pos.y!?
	// who cares, I'm just gonna disable it
	//
	@disable_trigger( trigger_pos_y_no_assign )
	//
	// `trigger_pos_x` still runs
	//
	y = 2;

	// runs `trigger_guys_moved` which succeeds
	//
	times_moved_guys += 1;
}

try_to_name_guy_but_fail :: (guy : *Guy, name : string) {

	// runs `trigger_guy_name` which fails
	//
	guy.name = name;
}


@trigger( "trigger_are_we_likely_to_succeed :: false" )
//
@trigger( "trigger_do_we_have_the_men :: false" )
//
@trigger( "trigger_is_deontology_better_than_consequentialism :: false" )
//
save :: (target : *Guy, using savior : *Guy) {
	target.saved_by = name;
}

main :: () {

	trigger_world :: (data : *Trigger_Data)
                     //
	                 -> *Trigger_Response {

		return null;
	}

	// attach trigger to a single local identifier
	//
	@trigger( trigger_world )
	//
	// reminds us to take good care of this data structure
	//
	world : World;

	// runs `trigger_guy_owned_in_main` which succeeds
	//
	@owner
	//
	guy : *Guy;

	try_to_name_guy_but_fail(guy, "Tom Hanks");

	// runs `trigger_guy_name` which succeeds
	// since the declaration has @owner
	//
	guy.name = "Tom Hanks";

	@owner
	guy2 : *Guy;
	guy2.name = "Private Ryan";

	// runs `trigger_world`
	//
	move_guy(guy, world);

	// this guy is fuckin' nuts,
	// it's like nothing can stop him!
	//
	@disable_all_triggers {

		private_ryan := cast(*Guy) search(&world, "Private Ryan");

		save(private_ryan, guy);
	}
}

///////                       ///////      ///////                       ///////
///////                       ///////      ///////                       ///////
///////                       ///////      ///////                       ///////
///////    implementation     ///////      ///////        begins         ///////
///////                       ///////      ///////                       ///////
///////                       ///////      ///////                       ///////
///////                       ///////      ///////                       ///////

compiler_message_loop_callback :: (message : *Compiler_Message) {

	using Compiler_Message.Kind;

	if message.kind != CODE_TYPECHECKED {
		return null;
	}

	tc :: cast(Compiler_Message_Code_Typechecked) message;

	decl :: tc.declaration;

	trigger_decl_user(decl);
}

// this procedure gets called by the build program while it's intercepting compiler messages
trigger_decl_user :: (decl : *Code_Declaration) {

	decl = trigger_decl_library(decl);

	data : Trigger_Data;

	if the declaration is for a procedure {

		for every statement in the procedure {

			for every expression in the statement {

				for every identifier in the expression {

					data.ident = identifier;
					data.expr = expression;
					data.stmt = statement;

					responses :: trigger_stmt_library(data);

					halt = false;

					for response : responses {

						if response.allowed == false {

							halt = true;

							printf(response.text);
						}

						<free memory somehow>
					}

					if halt {

						abort();
					}
				}
			}
		}
	}
}

Trigger_Data :: struct {

	ident : *Code_Ident;

	expr : *Code_Node;

	stmt : *Code_Statement;
}

// this could be a base class
Trigger_Response :: struct {

	text : string;

	allowed : bool = true;
}

Map :: struct (Key_Type : Type, Value_Type : Type) {

	keys   : *Key_Type;
	values : *Value_Type;

	count : size_t = 0;
}

add :: (using map : *Map, key : Key_Type, value : Value_Type) {

	// no idea where we get the memory

	keys[count] = key;
	values[count] = value;

	count += 1;
}

get :: (using map : *Map, key : Key_Type) -> [] Value_Type {

	results : [] Value_Type;

	for i : 0..count {

		if keys[i] == key {

			array_add(results, values[i]);
		}
	}

	return results;
}

has :: (using map : *Map, key : Key_Type, value : Value_Type) {

	for i : 0..count {

		if keys[i] == key && values[i] == value {

			return true;
		}
	}

	return false;
}
// we don't actually need a remove procedure

// the following are all one to many maps
//
trigger_map      : Map(*Code_Ident, [] *Code_Ident);
trigger_decl_map : Map(*Code_Ident, [] *Code_Ident);

disabled_block_map : Map(*Code_Statement, [] *Code_Ident);
disabled_decl_map  : Map(*Code_Statement, [] *Code_Ident);

// this procedure uses only the notes, so it could be called after parsing
//
trigger_decl_library :: (decl : *Code_Declaration) {

	for decl.notes {

		map : *Map(*Code_Ident, [] *Code_Procedure);

		triggering_ident : *Code_Ident;

		if the note is `@trigger(*)` {

			@Audit("is this the ident expression?")
			//
			triggering_ident = cast(*Code_Ident) decl.expressions[0];
			map = &trigger_map;
		}
		else if the note is `@trigger_decl(*)` {

			if `decl` is not a type declaration

				printf("@trigger_decl(*) attaches triggers to identifiers declared " +
				       "with the type that's tagged with the note");

				return;
			}

			@Audit("is this the ident expression?")
			//
			triggering_ident = cast(*Code_Ident) decl.expressions[0];
			map = &trigger_decl_map;
		}
		else {
			return;
		}


		if the first parameter is an ident referring to a procedure {

			add(map, triggering_ident, <the first parameter cast to an ident>);
		}

		if the first parameter is a string {

			compile_me := <the string>;

			if <the string> doesn't look like a declaration aka `<name> :: <right hand side>` {

				generate a name and set `compile_me` to `<generated name> :: <previous string>`
			}

			if `compile_me` is an alias, like "trigger_pos_y :: trigger_pos_x" {

				add a ; so it's a statement
			}


			if the <right hand side> is a boolean expression of trigger procedures or const booleans {

				make a procedure
				add a single return statement

				make procedure calls for all the idents in the expression
				and join them with the boolean expressions

				// Example:

				// the string "!proc1 && proc2 & bar ^ false"
				// becomes :Expanded
				/* 
					__trigger_394 :: (data : *Trigger_Data)
					                 //
					                 -> *Trigger_Response {

					 	response : *Trigger_Response = <get memory somehow>;

					 	p1 :: proc1(ident, expr, stmt);
					 	p2 :: proc2(ident, expr, stmt);

					 	response.allowed = !p1.allowed && p2.allowed & bar ^ false;

					 	if any of the procedures said the usage is not allowed {

					 		add lines about the specific grievances to `response.text`
					 	}

					 	return response;
					}
				*/
			}

			compile the string so it can be referred to later

			add(map, triggering_ident, <the ident of the compiled procedure>);
		}
	}

	return decl;
}

trigger_stmt_library :: (data : *Trigger_Data)
                        //
                        -> [] *Trigger_Response {

	responses : [] *Trigger_Response;

	map : *Map(*Code_Statement, *Code_Ident);

	disabled_stmt_map : Map(*Code_Statement, *Code_Ident);

	if stmt.expression.kind == {

		case DECLARATION:
			map = &disabled_decl_map;

		case BLOCK:
			map = &disabled_block_map;

		case:
			map = &disabled_stmt_map;
	}

	for note : stmt.notes {

		if note is `@disable_trigger(<ident>)` {

			add(map, stmt, <ident>);
		}

		if note is `@disable_all_triggers` {

			add(map, stmt, <some special ident>);
		}
	}

	for trigger : concat( get(trigger_map, ident), get(trigger_decl_map, ident.declaration) ) {

		if !is_trigger_disabled(ident, trigger) {

			response :: <the procedure with the ident>(ident, expr, stmt);

			if response == null {

				continue;
			}

			if response.allowed == false {

				array_add(responses, response);
			}
		}
	}

	is_trigger_disabled :: (ident : *Code_Ident, trigger : *Code_Ident)
	                       //
	                       -> bool {

		// @Speed
		// which ordering is optimal?

		return has(disabled_block_map, ident.block,       <some special ident>) ||
		       has(disabled_decl_map,  ident.declaration, <some special ident>) ||
		       has(disabled_stmt_map,  ident.declaration, <some special ident>)
		       ||
		       has(disabled_block_map, ident.block,       trigger) ||
		       has(disabled_decl_map,  ident.declaration, trigger) ||
		       has(disabled_stmt_map,  stmt,              trigger);
	}

	return responses;
}
```