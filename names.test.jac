"""Tests for names.sv.jac (SOH-212). Pure defs, no graph, no model."""

import from names { name_key, match_names, trim_words, display_how_met }

test "name_key strips honorifics, keeps parentheticals as an alias, drops trailing ?s" {
    k = name_key("prof Delgado (rosa)");
    assert k["clean"] == "Delgado";
    assert k["alias"] == "rosa";
    assert k["last"] == "";
    k2 = name_key("Dr. Helen Marsh-Whitcombe");
    assert k2["clean"] == "Helen Marsh-Whitcombe";
    assert k2["first"] == "helen" and k2["last"] == "marsh-whitcombe" and k2["initial"] == "m";
    assert k2["honorific"] == "Dr.";
    assert name_key("Reverend Okafor??")["clean"] == "Okafor";
    assert name_key("Maya O.")["last"] == "o";
    assert name_key("Dr.")["clean"] == "Dr.", "a lone honorific is kept rather than emptied";
}

test "match_names: the four persona pairs" {
    assert match_names("Helen", "Dr. Helen Marsh-Whitcombe") == "ambiguous";
    assert match_names("Maya O.", "Maya Okafor") == "ambiguous";
    assert match_names("Maya Lindqvist", "Maya Okafor") == "distinct";
    assert match_names("Mrs. Rosa Delgado", "Rosa Delgado") == "same";
    assert match_names("prof Delgado (rosa)", "Rosa Delgado") == "ambiguous";
}

test "trim_words / display_how_met cut on a word boundary with an ellipsis" {
    assert trim_words("short text", 60) == "short text";
    assert trim_words("Met Reverend Okafor after the county accessibility panel downtown", 60) == "Met Reverend Okafor after the county accessibility panel…";
    legacy = "debrief: " + "Met Reverend Okafor after the county accessibility panel downtown"[:60];
    shown = display_how_met(legacy);
    assert shown.endswith("accessibility panel…"), shown;
    assert display_how_met("intro via sam-lee") == "intro via sam-lee";
}
