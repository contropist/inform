[LocalParking::] Local Parking.

Like Free Parking in Monopoly, except that it is not free and has an overhead cost.

@ This is one of several devices we employ to get around the lack of a call stack
in memory. Suppose we want the local variables in function A to be visible to
function B, which is called from A, and suppose they cannot be passed as call
parameters to B. B cannot access them using pointers to the stack frame for A,
because the call stack does not exist in memory. What to do?

What we do is to stash them into a "local parking" array, make the call to B,
and then in the code for B retrieve them again. A paraphrase might look
like this:
= (text)
void A(void) {
	int alpha = 2, beta = 3, gamma = 5;
	lp[0] = alpha;
	lp[1] = beta;
	lp[2] = gamma;
	B();
}

void B(void) {
	int alpha = lp[0];
	int beta = lp[1];
	int gamma = lp[2];
	...
}
=
Note that B can now read, but not write, the locals from A. The scratch array
|lp| used here for storage is meaningless except for immediately before and
after the call to B, so we don't need to worry about multiple uses of local
parking getting in each other's way.

@ This compiles the necessary code before the call to B:

=
int LocalParking::park(stack_frame *frame) {
	int NC = 0;
	local_variable *lvar;
	LOOP_OVER_LOCALS_IN_FRAME(lvar, frame) NC++;
	inter_name *park = LocalParking::array((NC<2)?2:NC);
	inter_ti j = 0;
	LOOP_OVER_LOCALS_IN_FRAME(lvar, frame) {
		Produce::inv_primitive(Emit::tree(), SEQUENTIAL_BIP);
		Produce::down(Emit::tree());
			Produce::inv_primitive(Emit::tree(), STORE_BIP);
			Produce::down(Emit::tree());
				Produce::inv_primitive(Emit::tree(), LOOKUPREF_BIP);
				Produce::down(Emit::tree());
					Produce::val_iname(Emit::tree(), K_value, park);
					Produce::val(Emit::tree(), K_number, LITERAL_IVAL, j++);
				Produce::up(Emit::tree());
				inter_symbol *lvar_s = LocalVariables::declare(lvar);
				Produce::val_symbol(Emit::tree(), K_value, lvar_s);
			Produce::up(Emit::tree());
	}
	return NC;
}

@ And this compiles the retrieval code just after B begins:

=
void LocalParking::retrieve(stack_frame *frame) {
	inter_name *park = LocalParking::array(0);
	inter_ti j=0;
	local_variable *lvar;
	LOOP_OVER_LOCALS_IN_FRAME(lvar, frame) {
		Produce::inv_primitive(Emit::tree(), STORE_BIP);
		Produce::down(Emit::tree());
			Produce::ref_symbol(Emit::tree(), K_value, LocalVariables::declare(lvar));
			Produce::inv_primitive(Emit::tree(), LOOKUP_BIP);
			Produce::down(Emit::tree());
				Produce::val_iname(Emit::tree(), K_value, park);
				Produce::val(Emit::tree(), K_number, LITERAL_IVAL, j++);
			Produce::up(Emit::tree());
		Produce::up(Emit::tree());
	}
}

@ We just need |park| to be large enough for the maximum number of cars ever
needing to be parked:

=
int size_of_local_parking_area = 0;
inter_name *LocalParking::array(int N) {
	if (N > size_of_local_parking_area) size_of_local_parking_area = N;
	return Hierarchy::find(LOCALPARKING_HL);
}

@ We also sometimes need the same park to hold returned callings from deferred
propositions; and that needs to be large enough to hold values of up to 26
variables, plus a single other value.

=
inter_name *LocalParking::callings(void) {
	return LocalParking::array(27);
}

@ So this makes a suitably-sized car park, if one is needed at all:

=
void LocalParking::compile_array(void) {
	if (size_of_local_parking_area > 0) {
		inter_name *iname = LocalParking::array(0);
		packaging_state save = Emit::named_array_begin(iname, K_value);
		for (int i=0; i<size_of_local_parking_area; i++)
			Emit::array_numeric_entry(0);
		Emit::array_end(save);
		Hierarchy::make_available(Emit::tree(), iname);
	}
}