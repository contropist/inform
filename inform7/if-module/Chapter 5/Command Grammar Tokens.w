[CGTokens::] Command Grammar Tokens.

CGs are list of CG lines, which are lists of CG tokens.

@h Introduction.
Until 2021, CG tokens were held as parse nodes in the syntax tree, with a
special type |TOKEN_NT| and a set of annotations, but as cute as that was
it was also obfuscatory, and now each CG token corresponds to a //cg_token//
object as follows:

=
typedef struct cg_token {
	struct wording text_of_token;
	int grammar_token_code;
	struct parse_node *what_token_describes; /* 0 or else one of the |*_GTC| values */
	struct binary_predicate *token_relation;
	struct noun_filter_token *noun_filter;
	struct command_grammar *defined_by;
	int slash_class; /* used in slashing: see //CGLines::slash// */
	int slash_dash_dash; /* ditto */
	struct cg_token *next_token; /* in the list for a CG line */
	CLASS_DEFINITION
} cg_token;

cg_token *CGTokens::cgt_of(wording W, int lit) {
	cg_token *cgt = CREATE(cg_token);
	cgt->text_of_token = W;
	cgt->slash_dash_dash = FALSE;
	cgt->slash_class = 0;
	cgt->what_token_describes = NULL;
	cgt->grammar_token_code = lit?LITERAL_GTC:0;
	cgt->token_relation = NULL;
	cgt->noun_filter = NULL;
	cgt->defined_by = NULL;
	cgt->next_token = NULL;
	return cgt;
}

@h Text to a CG token list.
Tokens are created when text such as "drill [something] with [something]"
is parsed, from an Understand sentence or elsewhere. What happens is much
the same as when text with substitutions is read: the text is retokenised
by the lexer to produce the following, in which the square brackets have
become commas:
= (text)
"drill" , something , "with" , something
=
In fact we use a different punctuation set from the lexer's default, because
we want forward slashes to break words, so that we need |/| to be a punctuation
mark: thus "get away/off/out" becomes
= (text)
"get" "away" / "off" / "out"
=

@d GRAMMAR_PUNCTUATION_MARKS L".,:;?!(){}[]/" /* note the slash */

=
cg_token *CGTokens::tokenise(wording W) {
	wchar_t *as_wide_string = Lexer::word_text(Wordings::first_wn(W));
	@<Reject this if it contains punctuation@>;
	wording TW = Feeds::feed_C_string_full(as_wide_string, TRUE,
		GRAMMAR_PUNCTUATION_MARKS);
	@<Reject this if it contains two consecutive commas@>;

	cg_token *tokens = CGTokens::break_into_tokens(TW);
	if (tokens == NULL) {
		StandardProblems::sentence_problem(Task::syntax_tree(),
			_p_(PM_UnderstandEmptyText),
			"'understand' should be followed by text which contains at least "
			"one word or square-bracketed token",
			"so for instance 'understand \"take [something]\" as taking' is fine, "
			"but 'understand \"\" as the fog' is not. The same applies to the contents "
			"of 'topic' columns in tables, since those are also instructions for "
			"understanding.");
	}
	return tokens;
}

@<Reject this if it contains punctuation@> =
	int skip = FALSE, literal_punct = FALSE;
	for (int i=0; as_wide_string[i]; i++) {
		if (as_wide_string[i] == '[') skip = TRUE;
		if (as_wide_string[i] == ']') skip = FALSE;
		if (skip) continue;
		if ((as_wide_string[i] == '.') || (as_wide_string[i] == ',') ||
			(as_wide_string[i] == '!') || (as_wide_string[i] == '?') ||
			(as_wide_string[i] == ':') || (as_wide_string[i] == ';'))
			literal_punct = TRUE;
	}
	if (literal_punct) {
		StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_LiteralPunctuation),
			"'understand' text cannot contain literal punctuation",
			"or more specifically cannot contain any of these: . , ! ? : ; since they "
			"are already used in various ways by the parser, and would not correctly "
			"match here.");
		return NULL;
	}

@<Reject this if it contains two consecutive commas@> =
	LOOP_THROUGH_WORDING(i, TW)
		if (i < Wordings::last_wn(TW))
			if ((compare_word(i, COMMA_V)) && (compare_word(i+1, COMMA_V))) {
				StandardProblems::sentence_problem(Task::syntax_tree(),
					_p_(PM_UnderstandCommaCommand),
					"'understand' as an action cannot involve a comma",
					"since a command leading to an action never does. "
					"(Although Inform understands commands like 'PETE, LOOK' "
					"only the part after the comma is read as an action command: "
					"the part before the comma is read as the name of someone, "
					"according to the usual rules for parsing a name.) "
					"Because of the way Inform processes text with square "
					"brackets, this problem message is also sometimes seen "
					"if empty square brackets are used, as in 'Understand "
					"\"bless []\" as blessing.'");
				return NULL;
			}

@ The following tiny Preform grammar is then used to break up the resulting
text at commas:
=
<grammar-token-breaking> ::=
	... , ... |      ==> { NOT_APPLICABLE, - }
	<quoted-text> |  ==> { TRUE, - }
	...              ==> { FALSE, - }

@ The following function takes a wording and turns it into a linked list of
CG tokens, divided by commas:

=
cg_token *CGTokens::break_into_tokens(wording W) {
	return CGTokens::break_into_tokens_r(NULL, W);
}
cg_token *CGTokens::break_into_tokens_r(cg_token *list, wording W) {
	<grammar-token-breaking>(W);
	switch (<<r>>) {
		case NOT_APPLICABLE: {
			wording LW = GET_RW(<grammar-token-breaking>, 1);
			wording RW = GET_RW(<grammar-token-breaking>, 2);
			list = CGTokens::break_into_tokens_r(list, LW);
			list = CGTokens::break_into_tokens_r(list, RW);
			break;
		}
		case TRUE:
			Word::dequote(Wordings::first_wn(W));
			if (*(Lexer::word_text(Wordings::first_wn(W))) == 0) return list;
			W = Feeds::feed_C_string_full(Lexer::word_text(Wordings::first_wn(W)),
				FALSE, GRAMMAR_PUNCTUATION_MARKS);
			LOOP_THROUGH_WORDING(i, W) {
				cg_token *cgt = CGTokens::cgt_of(Wordings::one_word(i), TRUE);
				list = CGTokens::add_to_list(cgt, list);
			}
			break;
		case FALSE: {
			cg_token *cgt = CGTokens::cgt_of(W, FALSE);
			list = CGTokens::add_to_list(cgt, list);
			break;
		}
	}
	return list;
}

@ If |list| represents the head of the list (and is |NULL| for an empty list),
this adds |cgt| at the end and returns the new head.

=
cg_token *CGTokens::add_to_list(cg_token *cgt, cg_token *list) {
	if (list == NULL) return cgt;
	if (cgt == NULL) return list;
	cg_token *x = list;
	while (x->next_token) x = x->next_token;
	x->next_token = cgt;
	return list;
}

@ As the above shows, the text of a token is not necessarily a single word,
unless it's a literal.

=
wording CGTokens::text(cg_token *cgt) {
	return cgt?(cgt->text_of_token):(EMPTY_WORDING);
}

@h The GTC.
The GTC, or grammar token code, is a sort of type indicator for tokens. As
produced by the tokeniser above, tokens initially have GTC either |UNDETERMINED_GTC|
or |LITERAL_GTC|. Differentiation of non-literal tokens into other types happens
in //CGTokens::determine//.

Note that there are two sets of GTC values, one set positive, one negative. The
negative ones correspond closely to command-parser grammar reserved tokens in
the old I6 compiler, and this is indeed what they compile to if we are
generating I6 code.

@d NAMED_TOKEN_GTC 1
@d RELATED_GTC 2
@d STUFF_GTC 3
@d ANY_STUFF_GTC 4
@d ANY_THINGS_GTC 5
@d LITERAL_GTC 6

@d UNDETERMINED_GTC 0

@d NOUN_TOKEN_GTC -1        /* like I6 |noun| */
@d MULTI_TOKEN_GTC -2       /* like I6 |multi| */
@d MULTIINSIDE_TOKEN_GTC -3 /* like I6 |multiinside| */
@d MULTIHELD_TOKEN_GTC -4   /* like I6 |multiheld| */
@d HELD_TOKEN_GTC -5        /* like I6 |held| */
@d CREATURE_TOKEN_GTC -6    /* like I6 |creature| */
@d TOPIC_TOKEN_GTC -7       /* like I6 |topic| */
@d MULTIEXCEPT_TOKEN_GTC -8 /* like I6 |multiexcept| */

=
int CGTokens::is_literal(cg_token *cgt) {
	if ((cgt) && (cgt->grammar_token_code == LITERAL_GTC)) return TRUE;
	return FALSE;
}

int CGTokens::is_I6_parser_token(cg_token *cgt) {
	if ((cgt) && (cgt->grammar_token_code < 0)) return TRUE;
	return FALSE;
}

int CGTokens::is_topic(cg_token *cgt) {
	if ((cgt) && (cgt->grammar_token_code == TOPIC_TOKEN_GTC)) return TRUE;
	return FALSE;
}

@ A multiple token is one which permits multiple matches in the run-time command
parser: for instance, the player can type ALL where a |MULTI_TOKEN_GTC| is
expected.

=
int CGTokens::is_multiple(cg_token *cgt) {
	switch (cgt->grammar_token_code) {
		case MULTI_TOKEN_GTC:
		case MULTIINSIDE_TOKEN_GTC:
		case MULTIHELD_TOKEN_GTC:
		case MULTIEXCEPT_TOKEN_GTC:
			return TRUE;
	}
	return FALSE;
}

@h Logging.

=
void CGTokens::log(cg_token *cgt) {
	if (cgt == NULL) LOG("<no-cgt>");
	else {
		LOG("<CGT%d:%W", cgt->allocation_id, cgt->text_of_token);
		if (cgt->slash_class != 0) LOG("/%d", cgt->slash_class);
		if (cgt->slash_dash_dash) LOG("/--");
		switch (cgt->grammar_token_code) {
			case NAMED_TOKEN_GTC:        LOG(" = named token"); break;
			case RELATED_GTC:            LOG(" = related"); break;
			case STUFF_GTC:              LOG(" = stuff"); break;
			case ANY_STUFF_GTC:          LOG(" = any stuff"); break;
			case ANY_THINGS_GTC:         LOG(" = any things"); break;
			case NOUN_TOKEN_GTC:         LOG(" = noun"); break;
			case MULTI_TOKEN_GTC:        LOG(" = multi"); break;
			case MULTIINSIDE_TOKEN_GTC:  LOG(" = multiinside"); break;
			case MULTIHELD_TOKEN_GTC:    LOG(" = multiheld"); break;
			case HELD_TOKEN_GTC:         LOG(" = held"); break;
			case CREATURE_TOKEN_GTC:     LOG(" = creature"); break;
			case TOPIC_TOKEN_GTC:        LOG(" = topic"); break;
			case MULTIEXCEPT_TOKEN_GTC:  LOG(" = multiexcept"); break;
		}
		LOG(">");
	}
}

@h Parsing nonliteral tokens.
Unless a token is literal and in double-quotes, it will start out as having
|UNDETERMINED_GTC| until we investigate what the words in it mean, which we
will do with the following Preform grammar.

Note that <grammar-token> always matches any text, even if it sometimes throws
a problem message on the way. Its return integer is a valid GTC, and its
return pointer is a (non-null) description of what the token matches.

=
<grammar-token> ::=
	<named-grammar-token> |       ==> @<Apply the command grammar@>
	any things |                  ==> { ANY_THINGS_GTC, Specifications::from_kind(K_thing) }
	any <s-description> |         ==> { ANY_STUFF_GTC, RP[1] }
	anything |                    ==> { ANY_STUFF_GTC, Specifications::from_kind(K_thing) }
	anybody |                     ==> { ANY_STUFF_GTC, Specifications::from_kind(K_person) }
	anyone |                      ==> { ANY_STUFF_GTC, Specifications::from_kind(K_person) }
	anywhere |                    ==> { ANY_STUFF_GTC, Specifications::from_kind(K_room) }
	something related by reversed <relation-name> |   ==> @<Apply the reversed relation@>
	something related by <relation-name> |            ==> @<Apply the relation@>
	something related by ... |    ==> @<Issue PM_GrammarBadRelation problem@>
	<standard-grammar-token> |    ==> { pass 1 }
	<definite-article> <k-kind> | ==> { STUFF_GTC, Specifications::from_kind(RP[2]) }
	<s-description> |             ==> { STUFF_GTC, RP[1] }
	<s-type-expression>	|         ==> @<Issue PM_BizarreToken problem@>
	...                           ==> @<Issue PM_UnknownToken problem@>

<standard-grammar-token> ::=
	something |                 ==> { NOUN_TOKEN_GTC, Specifications::from_kind(K_object) }
	things |                    ==> { MULTI_TOKEN_GTC, Specifications::from_kind(K_object) }
	things inside |             ==> { MULTIINSIDE_TOKEN_GTC, Specifications::from_kind(K_object) }
	things preferably held |    ==> { MULTIHELD_TOKEN_GTC, Specifications::from_kind(K_object) }
	something preferably held | ==> { HELD_TOKEN_GTC, Specifications::from_kind(K_object) }
	other things |              ==> { MULTIEXCEPT_TOKEN_GTC, Specifications::from_kind(K_object) }
	someone	|                   ==> { CREATURE_TOKEN_GTC, Specifications::from_kind(K_object) }
	somebody |                  ==> { CREATURE_TOKEN_GTC, Specifications::from_kind(K_object) }
	text |                      ==> { TOPIC_TOKEN_GTC, Specifications::from_kind(K_understanding) }
	topic |                     ==> @<Issue PM_UseTextNotTopic problem@>
	a topic |                   ==> @<Issue PM_UseTextNotTopic problem@>
	object |                    ==> @<Issue PM_UseThingNotObject problem@>
	an object |                 ==> @<Issue PM_UseThingNotObject problem@>
	something held |            ==> @<Issue something held problem message@>
	things held                 ==> @<Issue things held problem message@>

<named-grammar-token> internal {
	command_grammar *cg = CommandGrammars::named_token_by_name(W);
	if (cg) {
		==> { -, cg };
		return TRUE;
	}
	==> { fail nonterminal };
}

@<Apply the command grammar@> =
	==> { NAMED_TOKEN_GTC, ParsingPlugin::rvalue_from_command_grammar(RP[1]) }

@<Apply the reversed relation@> =
	==> { RELATED_GTC, Rvalues::from_binary_predicate(BinaryPredicates::get_reversal(RP[1])) }

@<Apply the relation@> =
	==> { RELATED_GTC, Rvalues::from_binary_predicate(RP[1]) }

@<Issue PM_GrammarBadRelation problem@> =
	Problems::quote_source(1, current_sentence);
	Problems::quote_wording(2, W);
	StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_GrammarBadRelation));
	Problems::issue_problem_segment(
		"The grammar token '%2' in the sentence %1 "
		"invites me to understand names of related things, "
		"but the relation is not one that I know.");
	Problems::issue_problem_end();
	==> { RELATED_GTC, Rvalues::from_binary_predicate(R_equality) }

@<Issue PM_UseTextNotTopic problem@> =
	Problems::quote_source(1, current_sentence);
	Problems::quote_wording(2, W);
	StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_UseTextNotTopic));
	Problems::issue_problem_segment(
		"The grammar token '%2' in the sentence %1 would in some "
		"ways be the right logical way to suggest 'any words at "
		"all here', but Inform in actually uses the special syntax "
		"'[text]' for that. %P"
		"This is partly for historical reasons, but also because "
		"'[text]' is a token which can't be used in every sort of "
		"Understand grammar - for example, it can't be used with 'matches' "
		"or in descriptions of actions or in table columns; it's really "
		"intended only for defining new commands.");
	Problems::issue_problem_end();
	==> { TOPIC_TOKEN_GTC, Specifications::from_kind(K_understanding) };

@<Issue PM_UseThingNotObject problem@> =
	Problems::quote_source(1, current_sentence);
	Problems::quote_wording(2, W);
	StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_UseThingNotObject));
	Problems::issue_problem_segment(
		"The grammar token '%2' in the sentence %1 would in some "
		"ways be the right logical way to suggest 'any object at "
		"all here', but Inform uses the special syntax '[thing]' "
		"for that. (Or '[things]' if multiple objects are allowed.)");
	Problems::issue_problem_end();
	==> { MULTI_TOKEN_GTC, Specifications::from_kind(K_object) }

@<Issue something held problem message@> =
	CGTokens::incompatible_change_problem(
		"something held", "something", "something preferably held");
	==> { HELD_TOKEN_GTC, Specifications::from_kind(K_object) }

@<Issue things held problem message@> =
	CGTokens::incompatible_change_problem(
			"things held", "things", "things preferably held");
	==> { MULTIHELD_TOKEN_GTC, Specifications::from_kind(K_object) }

@<Issue PM_BizarreToken problem@> =
	LOG("$T", current_sentence);
	Problems::quote_source(1, current_sentence);
	Problems::quote_wording(2, W);
	Problems::quote_kind_of(3, RP[1]);
	StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_BizarreToken));
	Problems::issue_problem_segment(
		"The grammar token '%2' in the sentence %1 looked to me as "
		"if it might be %3, but this isn't something allowed in "
		"parsing grammar.");
	Problems::issue_problem_end();
	==> { STUFF_GTC, Specifications::from_kind(K_thing) }

@<Issue PM_UnknownToken problem@> =
	LOG("$T", current_sentence);
	Problems::quote_source(1, current_sentence);
	Problems::quote_wording(2, W);
	StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_UnknownToken));
	Problems::issue_problem_segment(
		"I was unable to understand what you meant by the grammar token '%2' "
		"in the sentence %1.");
	Problems::issue_problem_end();
	==> { STUFF_GTC, Specifications::from_kind(K_thing) }

@ Something of an extended mea culpa: but it had the desired effect, in
that nobody complained about what might have been a controversial change.

=
void CGTokens::incompatible_change_problem(char *token_tried, char *token_instead,
	char *token_better) {
	Problems::quote_source(1, current_sentence);
	Problems::quote_text(2, token_tried);
	Problems::quote_text(3, token_instead);
	Problems::quote_text(4, token_better);
	StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_ObsoleteHeldTokens));
	Problems::issue_problem_segment(
		"In the sentence %1, you used the '[%2]' as a token, which was "
		"allowed in the early Public Beta versions of Inform 7, but became "
		"out of date in August 2006.%L A change was then made so that if an "
		"action needed to apply to something which was carried, this would "
		"now be specified when the action is created - not in the Understand "
		"line for it. For instance, one might say 'Dismantling is an action "
		"which applies to one carried thing', instead of '...which applies "
		"to one thing', and then write grammar such as 'Understand \"dismantle "
		"[something] as dismantling' instead of '...[something held]...'. "
		"So you probably need to change your '[%2]' token to '[%3]', and "
		"change the action's definition (unless it is a built-in action "
		"such as 'dropping'). An alternative, though, for fine-tuning is to "
		"change it to '[%4]', which allows anything to be Understood, but "
		"in cases of ambiguity tends to guess that something held is more "
		"likely to be what the player means than something not held.");
	Problems::issue_problem_end();
}

@h Determining.
To calculate a description of what is being described by a token, then, we
call the following function, which delegates to <grammar-token> above.

In the two cases |NAMED_TOKEN_GTC| and |RELATED_GTC| the pointer result is
a temporary one telling us which named token, and which relation, respectively:
we then convert those into the result. In all other cases, the |parse_node|
pointer returned by <grammar-token> is the result.

=
parse_node *CGTokens::determine(cg_token *cgt, int depth) {
	if (CGTokens::is_literal(cgt)) return NULL;

	<grammar-token>(CGTokens::text(cgt));
	cgt->grammar_token_code = <<r>>;
	parse_node *result = <<rp>>;

	switch (cgt->grammar_token_code) {
		case NAMED_TOKEN_GTC:
			cgt->defined_by = ParsingPlugin::rvalue_to_command_grammar(result);
			result = CommandGrammars::determine(cgt->defined_by, depth+1);
			break;
		case ANY_STUFF_GTC:
			@<Make sure the result is a description with one free variable@>;
			cgt->noun_filter = UnderstandFilterTokens::nft_new(result, TRUE, FALSE);
			break;
		case ANY_THINGS_GTC:
			@<Make sure the result is a description with one free variable@>;
			cgt->noun_filter = UnderstandFilterTokens::nft_new(result, TRUE, TRUE);
			break;
		case RELATED_GTC:
			cgt->token_relation = Rvalues::to_binary_predicate(result);
			kind *K = BinaryPredicates::term_kind(cgt->token_relation, 0);
			if (K == NULL) K = K_object;
			result = Specifications::from_kind(K);
			break;
		case STUFF_GTC:
			@<Make sure the result is a description with one free variable@>;
			cgt->noun_filter = UnderstandFilterTokens::nft_new(result, FALSE, FALSE);
			break;
		default:
			Node::set_text(result, CGTokens::text(cgt));
			break;
	}

	if (result) @<Vet the grammar token determination for parsability at run-time@>;
	cgt->what_token_describes = result;
	return cgt->what_token_describes;
}

@ If the token determines an actual constant value -- as it can when it is a
named token which always refers to a specific thing, for example -- it is
possible for |result| not to be a description. Otherwise, though, it has to
be a description which is true or false for any given value, so:

@<Make sure the result is a description with one free variable@> =
	pcalc_prop *prop = Specifications::to_proposition(result);
	if ((prop) && (Binding::number_free(prop) != 1)) {
		LOG("So $P and $D\n", result, prop);
		StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_FilterQuantified),
			"the [any ...] doesn't clearly give a description in the '...' part",
			"where I was expecting something like '[any vehicle]'.");
		result = Specifications::from_kind(K_object);
	}

@<Vet the grammar token determination for parsability at run-time@> =
	if (Specifications::is_description(result)) {
		kind *K = Specifications::to_kind(result);
		if ((K_understanding) &&
			(Kinds::Behaviour::is_object(K) == FALSE) &&
			(Kinds::eq(K, K_understanding) == FALSE) &&
			(Kinds::Behaviour::request_I6_GPR(K) == FALSE)) {
			Problems::quote_source(1, current_sentence);
			Problems::quote_wording(2, CGTokens::text(cgt));
			StandardProblems::handmade_problem(Task::syntax_tree(), _p_(PM_UnparsableKind));
			Problems::issue_problem_segment(
				"The grammar token '%2' in the sentence %1 invites me to understand "
				"values typed by the player during play but for a kind of value which "
				"is beyond my ability. Generally speaking, the allowable kinds of value "
				"are number, time, text and any new kind of value you may have created - "
				"but not, for instance, scene or rule.");
			Problems::issue_problem_end();
			result = Specifications::from_kind(K_object);
		}
	}

@h Scoring.
This score is needed when sorting CG lines in order of applicability: see the
discussion at //CGLines::cgl_determine//. The function must return a value
which is at least 0 but strictly less than |CGL_SCORE_TOKEN_RANGE|. The
general idea is that higher scores cause tokens to take precedence over lower
ones.

=
int CGTokens::score_bonus(cg_token *cgt) {
	if (cgt == NULL) internal_error("no cgt");
	if (cgt->grammar_token_code == UNDETERMINED_GTC) internal_error("undetermined");
	int gtc = cgt->grammar_token_code;
	switch(gtc) {
		case STUFF_GTC:             return 5;
        case NOUN_TOKEN_GTC:        return 1;
        case MULTI_TOKEN_GTC:       return 1;
        case MULTIINSIDE_TOKEN_GTC: return 2;
        case MULTIHELD_TOKEN_GTC:   return 3;
        case HELD_TOKEN_GTC:        return 4;
        case CREATURE_TOKEN_GTC:    return 1;
        case TOPIC_TOKEN_GTC:       return 0;
        case MULTIEXCEPT_TOKEN_GTC: return 3;
	}
	return 1;
}