[SynopticResponses::] Responses.

To compile the main/synoptic/responses submodule.

@ Before this runs, response packages are scattered all over the Inter tree.
We must allocate each one a unique ID in the range 1, 2, 3, ...; these will
be the enumerated values of the kind |K_response|.

Response packages contain four metadata constants:
(*) |^group|, textual, which describes the origin.
(*) |^marker|, numeric, from 0 to 25: whether this is (A), (B), ..., (Z);
(*) |^rule|, symbol, the rule to which this is a response.
(*) |^value|, symbol, the text for the response at start of play.

As this is called, //Synoptic Utilities// has already formed a list |response_nodes|
of packages of type |_response|. Each of these contains a constant called
|response_id|, which the Inform compiler created as just 0; we substitute the
correct ID.

=
void SynopticResponses::compile(inter_tree *I, inter_tree_location_list *response_nodes) {
	if (TreeLists::len(response_nodes) > 0) {
		for (int i=0; i<TreeLists::len(response_nodes); i++) {
			inter_package *pack = Inter::Package::defined_by_frame(response_nodes->list[i].node);
			inter_tree_node *D = Synoptic::get_definition(pack, I"response_id");
			D->W.data[DATA_CONST_IFLD+1] = (inter_ti) i+1;
		}
	}
	@<Define NO_RESPONSES@>;
	@<Define ResponseTexts array@>;
	@<Define ResponseDivisions array@>;
	@<Define PrintResponse function@>;
}

@<Define NO_RESPONSES@> =
	inter_name *iname = HierarchyLocations::find(I, NO_RESPONSES_HL);
	Produce::numeric_constant(I, iname, K_value, (inter_ti) (TreeLists::len(response_nodes)));

@ This is the critical array which connects a response ID to the current value
of the text of that response.

@<Define ResponseTexts array@> =
	inter_name *iname = HierarchyLocations::find(I, RESPONSETEXTS_HL);
	Synoptic::begin_array(I, iname);
	for (int i=0; i<TreeLists::len(response_nodes); i++) {
		inter_package *pack = Inter::Package::defined_by_frame(response_nodes->list[i].node);
		inter_symbol *value_s = Metadata::read_symbol(pack, I"^value");
		Synoptic::symbol_entry(value_s);
	}
	Synoptic::numeric_entry(0);
	Synoptic::numeric_entry(0);
	Synoptic::end_array(I);

@ The following array is used only by the testing command RESPONSES, and
enables the Inter template to print out all known responses at run-time,
divided up by the extensions containing the rules which produce them.
(The main compiler created only an empty array.)

The format is triples |(group, from, to)| where |group| is a textual
description of the origin of the set (e.g., an extension name), and |from|
and |to| are an inclusive range of response ID numbers. (This means they
are higher by 1 than the corresponding indices in the |response_nodes| list.)
The triple |(0, 0, 0)| ends the array.

@<Define ResponseDivisions array@> =
	inter_name *iname = HierarchyLocations::find(I, RESPONSEDIVISIONS_HL);
	Synoptic::begin_array(I, iname);
	text_stream *current_group = NULL; int start_pos = -1;
	for (int i=0; i<TreeLists::len(response_nodes); i++) {
		inter_package *pack = Inter::Package::defined_by_frame(response_nodes->list[i].node);
		text_stream *group = Metadata::read_textual(pack, I"^group");
		if (Str::ne(group, current_group)) {
			if (start_pos >= 0) {
				Synoptic::textual_entry(current_group);
				Synoptic::numeric_entry((inter_ti) start_pos + 1);
				Synoptic::numeric_entry((inter_ti) i);
			}
			current_group = group;
			start_pos = i;
		}
	}
	if (start_pos >= 0) {
		Synoptic::textual_entry(current_group);
		Synoptic::numeric_entry((inter_ti) start_pos + 1);
		Synoptic::numeric_entry((inter_ti) TreeLists::len(response_nodes));
	}
	Synoptic::numeric_entry(0);
	Synoptic::numeric_entry(0);
	Synoptic::numeric_entry(0);
	Synoptic::end_array(I);

@ Finally, a function used when printing values of the |K_response| kind;
the main compiler created this as a mostly empty function with two local
variables -- |R|, the ID for the response we should print, and |RPR|, the
address of a function for printing rule names.

This is in effect a big switch statement, so it's not fast; but being a print
function it doesn't need to be.

The only reason this is a function at all, rather than using far more
efficient array lookups, is that we have to guard accessible memory space on
the Z-machine, where such an array could consume over 1K, but where memory for
code is less limited.

@<Define PrintResponse function@> =
	inter_name *iname = HierarchyLocations::find(I, PRINT_RESPONSE_HL);
	Synoptic::begin_function(I, iname);
	inter_symbol *R_s = Synoptic::local(I, I"R", NULL);

	for (int i=0; i<TreeLists::len(response_nodes); i++) {
		inter_package *pack = Inter::Package::defined_by_frame(response_nodes->list[i].node);
		inter_ti m = Metadata::read_numeric(pack, I"^marker");
		inter_symbol *rule_s = Metadata::read_symbol(pack, I"^value");
		Produce::inv_primitive(I, IF_BIP);
		Produce::down(I);
			Produce::inv_primitive(I, EQ_BIP);
			Produce::down(I);
				Produce::val_symbol(I, K_value, R_s);
				Produce::val(I, K_value, LITERAL_IVAL, (inter_ti) i+1);
			Produce::up(I);
			Produce::code(I);
			Produce::down(I);
				Produce::inv_call_iname(I, HierarchyLocations::find(I, RULEPRINTINGRULE_HL));
				Produce::down(I);
					Produce::val_symbol(I, K_value, rule_s);
				Produce::up(I);
				Produce::inv_primitive(I, PRINT_BIP);
				Produce::down(I);
					Produce::val_text(I, I" response (");
				Produce::up(I);
				Produce::inv_primitive(I, PRINTCHAR_BIP);
				Produce::down(I);
					Produce::val(I, K_value, LITERAL_IVAL, (inter_ti) ('A' + m));
				Produce::up(I);
				Produce::inv_primitive(I, PRINT_BIP);
				Produce::down(I);
					Produce::val_text(I, I")");
				Produce::up(I);
			Produce::up(I);
		Produce::up(I);
	}
	Synoptic::end_function(I, iname);