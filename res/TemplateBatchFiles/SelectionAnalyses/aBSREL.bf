RequireVersion ("2.31");



LoadFunctionLibrary("libv3/all-terms.bf"); // must be loaded before CF3x4

LoadFunctionLibrary("GrabBag");
LoadFunctionLibrary("CF3x4");
LoadFunctionLibrary("TreeTools");


// namespace 'utility' for convenience functions
LoadFunctionLibrary("libv3/UtilityFunctions.bf");

// namespace 'io' for interactive/datamonkey i/o functions
LoadFunctionLibrary("libv3/IOFunctions.bf");

LoadFunctionLibrary ("libv3/models/codon/MG_REV.bf");

// namespace 'estimators' for various estimator related functions
LoadFunctionLibrary("libv3/tasks/estimators.bf");

// namespace 'estimators' for various estimator related functions
LoadFunctionLibrary("libv3/tasks/alignments.bf");

// namespace 'estimators' for various estimator related functions
LoadFunctionLibrary("libv3/tasks/trees.bf");

LoadFunctionLibrary("modules/io_functions.ibf");
LoadFunctionLibrary("modules/selection_lib.ibf");
LoadFunctionLibrary("libv3/models/codon/BS_REL.bf");
LoadFunctionLibrary("libv3/convenience/math.bf");


utility.SetEnvVariable ("NORMALIZE_SEQUENCE_NAMES", TRUE);
utility.SetEnvVariable ("ASSUME_REVERSIBLE_MODELS", TRUE);




/*------------------------------------------------------------------------------*/

absrel.json    = {
                    terms.json.input: {},
                    terms.json.fits : {},
                    terms.json.timers : {},
                    terms.json.test_results : {}
                  };

absrel.max_rate_classes  = 5;
absrel.MG94 = "MG94xREV with separate dN/dS for each branch";

absrel.p_threshold = 0.05;

/*------------------------------------------------------------------------------*/


absrel.analysis_description = {terms.io.info : "aBSREL (Adaptive branch-site random effects likelihood)
                            uses an adaptive random effects branch-site model framework
                            to test whether each branch has evolved under positive selection,
                            using a procedure which infers an optimal number of rate categories per branch.",
                           terms.io.version : "2.0",
                           terms.io.reference : "Less Is More: An Adaptive Branch-Site Random Effects Model for Efficient Detection of Episodic Diversifying Selection (2015). Mol Biol Evol 32 (5): 1342-1353",
                           terms.io.authors : "Sergei L Kosakovsky Pond, Ben Murrell, Steven Weaver and Temple iGEM / UCSD viral evolution group",
                           terms.io.contact : "spond@temple.edu",
                           terms.io.requirements : "in-frame codon alignment and a phylogenetic tree"
                          };

io.DisplayAnalysisBanner ( absrel.analysis_description );

selection.io.startTimer (absrel.json [terms.json.timers], "Overall", 0);

namespace absrel {
    LoadFunctionLibrary ("modules/shared-load-file.bf");
    load_file ("absrel");
}

io.CheckAssertion("utility.Array1D (absrel.partitions_and_trees) == 1", "aBSREL only works on a single partition dataset");


utility.ForEachPair (absrel.selected_branches, "_partition_", "_selection_",
    "_selection_ = utility.Filter (_selection_, '_value_', '_value_ == terms.tree_attributes.test');
     io.ReportProgressMessageMD('RELAX',  'selector', '* Selected ' + Abs(_selection_) + ' branches for testing: \\\`' + Join (', ',utility.Keys(_selection_)) + '\\\`')");



/*
absrel.srv = io.SelectAnOption ({
                                        {"Yes", "Both synonymous and non-synonymous rates vary in a branch-site fashion (~5x more computationally expensive)"}
                                        {"No", "[Default] Synonymous rates vary from branch to branch, while the dN/dS ratio varies among branch-site combinations"}
                                    }, "Enable synonymous rate variation?");
*/

selection.io.startTimer (absrel.json [terms.json.timers], "Preliminary model fitting", 1);


namespace absrel {
    doGTR ("absrel");
}

selection.io.stopTimer (absrel.json [terms.json.timers], "Preliminary model fitting");
selection.io.startTimer (absrel.json [terms.json.timers], "Baseline model fitting", 2);

io.ReportProgressMessageMD ("absrel", "base", "Fitting the baseline model with a single dN/dS class per branch, and no site-to-site variation. ");

absrel.base.results = estimators.FitMGREV (absrel.filter_names, absrel.trees, absrel.codon_data_info [terms.code], {
    terms.run_options.model_type: terms.local,
    terms.run_options.retain_lf_object: TRUE,
    terms.run_options.retain_model_object : TRUE
}, absrel.gtr_results);

io.ReportProgressMessageMD("absrel", "base", "* " + selection.io.report_fit (absrel.base.results, 0, absrel.codon_data_info[terms.data.sample_size]));



selection.io.json_store_branch_attribute(absrel.json, terms.original_name, terms.json.node_label, 0,
                                         0,
                                         absrel.name_mapping);

absrel.baseline.branch_lengths = selection.io.extract_branch_info((absrel.base.results[terms.branch_length])[0], "selection.io.branch.length");
absrel.baseline.omegas = selection.io.extract_branch_info((absrel.base.results[terms.branch_length])[0], "absrel.local.omega");

absrel.omega_stats = math.GatherDescriptiveStats (utility.Map (utility.Values (absrel.baseline.omegas), "_value_", "0+_value_"));

io.ReportProgressMessageMD("absrel", "base", "* Branch-level `terms.parameters.omega_ratio` distribution has mean " + Format (absrel.omega_stats[terms.math.mean], 5,2) + ", median " +
                                             Format (absrel.omega_stats[terms.math.median], 5,2) + ", and 95% of the weight in " + Format (absrel.omega_stats[terms.math._2.5], 5,2) + " - " + Format (absrel.omega_stats[terms.math._97.5], 5,2));


selection.io.json_store_branch_attribute(absrel.json, "Baseline MG94xREV", terms.branch_length, 1,
                                                      0,
                                                      absrel.baseline.branch_lengths);

selection.io.json_store_branch_attribute(absrel.json, "Baseline dN/dS ratio", terms.json.branch_label, 1,
                                                      0,
                                                      absrel.baseline.omegas);

selection.io.stopTimer (absrel.json [terms.json.timers], "Baseline model fitting");

// TODO -- there's gotta be a better way to do this
absrel.branch_count = Abs (absrel.baseline.branch_lengths);
absrel.sorted_branch_lengths = {absrel.branch_count, 2};
absrel.bnames = utility.Keys (absrel.baseline.branch_lengths);
utility.ForEachPair (absrel.bnames, "_index_", "_value_",
        '
            absrel.sorted_branch_lengths [_index_[1]][0] = absrel.baseline.branch_lengths[_value_];
            absrel.sorted_branch_lengths [_index_[1]][1] = _index_[1];
        ');
absrel.sorted_branch_lengths  = absrel.sorted_branch_lengths % 0;
absrel.names_sorted_by_length = {absrel.branch_count, 1};

for (absrel.i = absrel.branch_count - 1; absrel.i >= 0;  absrel.i = absrel.i - 1) {
    absrel.names_sorted_by_length [absrel.branch_count - 1 - absrel.i] =  absrel.bnames [absrel.sorted_branch_lengths[absrel.i][1]];
}

absrel.distribution_for_json = {'Per-branch dN/dS' :
                                    {terms.math.mean : absrel.omega_stats[terms.math.mean],
                                    terms.math.median : absrel.omega_stats[terms.math.median],
                                    terms.math._2.5 : absrel.omega_stats[terms.math._2.5],
                                    terms.math._97.5 : absrel.omega_stats[terms.math._97.5]}
                               };

selection.io.json_store_lf_spool (absrel.codon_data_info [terms.json.json], absrel.json,
                            "Baseline",
                            absrel.base.results[terms.fit.log_likelihood],
                            absrel.base.results[terms.parameters] ,
                            absrel.codon_data_info[terms.data.sample_size],
                            absrel.distribution_for_json);

// define BS-REL models with up to N rate classes

absrel.model_defintions = {};

absrel.likelihood_function_id = absrel.base.results [terms.likelihood_function];
absrel.constrain_everything (absrel.likelihood_function_id);
absrel.tree_id = absrel.get_tree_name (absrel.likelihood_function_id);
absrel.model_id = absrel.get_model_id (absrel.likelihood_function_id);
absrel.MG94.model = (absrel.base.results[terms.model])[(utility.Keys (absrel.base.results[terms.model]))[0]];

selection.io.startTimer (absrel.json [terms.json.timers], "Complexity analysis", 3);

for (absrel.i = 2; absrel.i <= absrel.max_rate_classes; absrel.i += 1) {
    absrel.model_defintions [absrel.i] = model.generic.DefineMixtureModel("absrel.BS_REL.ModelDescription",
            "absrel.model." + absrel.i, {
                "0": parameters.Quote(terms.local),
                "1": absrel.codon_data_info[terms.code],
                "2": parameters.Quote (absrel.i) // the number of rate classes
            },
            absrel.filter_names,
            None);

    models.BindGlobalParameters ({"1" : absrel.model_defintions [absrel.i], "0" : absrel.MG94.model}, terms.nucleotideRate("[ACGT]","[ACGT]"));
}

io.ReportProgressMessageMD ("absrel", "complexity", "Determining the optimal number of rate classes per branch using a step up procedure");


absrel.current_parameter_count    = absrel.base.results[terms.parameters];
absrel.current_best_score         = math.GetIC (absrel.base.results[terms.fit.log_likelihood], absrel.current_parameter_count, absrel.codon_data_info[terms.data.sample_size]);
absrel.complexity.by_branch       = {};

utility.ToggleEnvVariable ("USE_LAST_RESULTS", TRUE);

for (absrel.branch_id = 0; absrel.branch_id < absrel.branch_count; absrel.branch_id += 1) {

    absrel.current_branch           = absrel.names_sorted_by_length[absrel.branch_id];
    absrel.current_branch_estimates = absrel.GetBranchEstimates (absrel.MG94.model, absrel.tree_id, absrel.current_branch);
    io.ReportProgressMessageMD ("absrel", "complexity", "* Examining branch `absrel.current_branch` (length = " + Format (absrel.baseline.branch_lengths[absrel.current_branch], 8, 6) + ")");

    absrel.current_rate_count = 2;

    while (TRUE) {
        model.ApplyToBranch ((absrel.model_defintions [absrel.current_rate_count])[terms.id], absrel.tree_id, absrel.current_branch);
        parameters.SetValues (absrel.current_branch_estimates);

        absrel.initial_guess = absrel.ComputeOnAGrid (absrel.PopulateInitialGrid (absrel.model_defintions [absrel.current_rate_count], absrel.tree_id, absrel.current_branch, absrel.current_branch_estimates), absrel.likelihood_function_id);

        absrel.SetBranchConstraints (absrel.model_defintions [absrel.current_rate_count], absrel.tree_id, absrel.current_branch);

        //VERBOSITY_LEVEL = 10;

        Optimize (absrel.stepup.mles, ^absrel.likelihood_function_id);
        absrel.current_test_score = math.GetIC (absrel.stepup.mles[1][0], absrel.current_parameter_count + 2, absrel.codon_data_info[terms.data.sample_size]);
        absrel.delta = absrel.current_best_score-absrel.current_test_score;
        if (absrel.delta > 0) {
            io.ReportProgressMessageMD ("absrel", "complexity", "    * A " + absrel.current_rate_count + "-rate model yielded Log(L) =  " + Format(absrel.stepup.mles[1][0],8,2) + ", which is a " + Format (absrel.current_best_score-absrel.current_test_score,8,2) + " point _improvement_ in AIC-c");
        } else {
            io.ReportProgressMessageMD ("absrel", "complexity", "    * A " + absrel.current_rate_count + "-rate model yielded Log(L) =  " + Format(absrel.stepup.mles[1][0],8,2) + ", which is a " + Format (absrel.current_best_score-absrel.current_test_score,8,2) + " point _regression_  in AIC-c");
        }

        if (absrel.current_test_score < absrel.current_best_score) {
            absrel.current_branch_estimates = absrel.GetBranchEstimates(absrel.model_defintions [absrel.current_rate_count], absrel.tree_id, absrel.current_branch);
            absrel.current_best_score = absrel.current_test_score;
            if (absrel.current_rate_count >= absrel.max_rate_classes) {
                break;
            }
            absrel.current_rate_count      += 1;
            absrel.current_parameter_count += 2;
        } else {
            break;
        }
    }

    if (absrel.current_test_score >= absrel.current_best_score) { // reset the model
        absrel.current_rate_count = absrel.current_rate_count - 1;
        if ( absrel.current_rate_count >= 2) {
            model.ApplyToBranch ((absrel.model_defintions [absrel.current_rate_count])[terms.id], absrel.tree_id, absrel.current_branch);
            absrel.SetBranchConstraints (absrel.model_defintions [absrel.current_rate_count], absrel.tree_id, absrel.current_branch);
        } else {
            model.ApplyToBranch (absrel.MG94.model[terms.id], absrel.tree_id, absrel.current_branch);
        }
        parameters.SetValues (absrel.current_branch_estimates);
    }

    io.ReportProgressMessageMD ("absrel", "complexity", "    * **" + absrel.current_rate_count + "** rate classes have been selected");

    absrel.complexity.by_branch [absrel.current_branch] = absrel.current_rate_count;
    absrel.constrain_everything (absrel.likelihood_function_id);

}

console.log (absrel.complexity.by_branch);

selection.io.stopTimer (absrel.json [terms.json.timers], "Complexity analysis");


utility.ToggleEnvVariable ("USE_LAST_RESULTS", None);


return absrel.json;

//------------------------------------------------------------------------------------------------------------------------
//------------------------------------------------------------------------------------------------------------------------
//------------------------------------------------------------------------------------------------------------------------

lfunction absrel.GetBranchEstimates (model, tree_id, branch_id) {
    values = {};
    utility.ForEachPair ((model[utility.getGlobalValue ("terms.parameters")])[utility.getGlobalValue ("terms.local")],
                         "_description_",
                         "_id_",
                         "`&values`[_description_] = {
                            terms.fit.MLE : Eval (`&tree_id` + '.' + `&branch_id` + '.' + _id_),
                            terms.id : `&tree_id` + '.' + `&branch_id` + '.' + _id_
                         };");

    return values;
}

//------------------------------------------------------------------------------------------------------------------------

lfunction absrel.SetBranchConstraints (model, tree_id, branch_id) {
    component_count = model[utility.getGlobalValue ("terms.model.components")];
    local_parameters = (model[utility.getGlobalValue ("terms.parameters")])[utility.getGlobalValue ("terms.local")];
    parameters.SetRange ("`tree_id`.`branch_id`.`local_parameters[utility.getGlobalValue ('terms.parameters.synonymous_rate')]`", {utility.getGlobalValue ("terms.lower_bound") : "0", utility.getGlobalValue ("terms.upper_bound") : "50"});
    for (k = 1; k < component_count; k+=1) {
        omega_k   = terms.AddCategory (utility.getGlobalValue('terms.parameters.omega_ratio'), k);
        parameters.SetRange ("`tree_id`.`branch_id`.`local_parameters[omega_k]`", utility.getGlobalValue ("terms.range01"));
    }
    omega_k   = terms.AddCategory (utility.getGlobalValue('terms.parameters.omega_ratio'), k);
    parameters.SetRange ("`tree_id`.`branch_id`.`local_parameters[omega_k]`", utility.getGlobalValue ("terms.range_any"));
}

//------------------------------------------------------------------------------------------------------------------------

lfunction absrel.PopulateInitialGrid (model, tree_id, branch_id, current_estimates) {

    component_count = model[utility.getGlobalValue ("terms.model.components")];
    local_parameters = (model[utility.getGlobalValue ("terms.parameters")])[utility.getGlobalValue ("terms.local")];

    grid = {};

    if (component_count == 2) {
        omega1   = terms.AddCategory (utility.getGlobalValue('terms.parameters.omega_ratio'), 1);
        omega2   = terms.AddCategory (utility.getGlobalValue('terms.parameters.omega_ratio'), 2);
        mixture1 = terms.AddCategory (utility.getGlobalValue("terms.mixture.mixture_aux_weight"), 1 );

        grid ["`tree_id`.`branch_id`.`local_parameters[^'terms.parameters.synonymous_rate']`"] = {5,1}["(current_estimates[^'terms.parameters.synonymous_rate'])[^'terms.fit.MLE']*(1+(2-_MATRIX_ELEMENT_ROW_)*0.25)"];
        grid ["`tree_id`.`branch_id`.`local_parameters[omega1]`"]   = {5,1}["_MATRIX_ELEMENT_ROW_ * 0.2"];
        grid ["`tree_id`.`branch_id`.`local_parameters[omega2]`"]   = {7,1}["(1+(_MATRIX_ELEMENT_ROW_-3)^3)*(_MATRIX_ELEMENT_ROW_>=3)+(_MATRIX_ELEMENT_ROW_*0.25+0.25)*(_MATRIX_ELEMENT_ROW_<3)"];
        grid ["`tree_id`.`branch_id`.`local_parameters[mixture1]`"] = {{0.98}{0.95}{0.90}{0.75}{0.5}};
    } else {
        omega_prev = current_estimates [terms.AddCategory (utility.getGlobalValue('terms.parameters.omega_ratio'), component_count - 1)];
        omega_last = terms.AddCategory (utility.getGlobalValue('terms.parameters.omega_ratio'), component_count);
        mixture_last = terms.AddCategory (utility.getGlobalValue("terms.mixture.mixture_aux_weight"),  component_count - 1);
        if (omega_prev [utility.getGlobalValue('terms.fit.MLE')] > 1) {
            parameters.SetValue (omega_prev [utility.getGlobalValue('terms.id')], 0.8);
        }
        grid ["`tree_id`.`branch_id`.`local_parameters[omega_last]`"]   = {10,1}["(1+(_MATRIX_ELEMENT_ROW_-5)^3)*(_MATRIX_ELEMENT_ROW_>=5)+(_MATRIX_ELEMENT_ROW_*0.15+0.15)*(_MATRIX_ELEMENT_ROW_<5)"];
        grid ["`tree_id`.`branch_id`.`local_parameters[mixture_last]`"] = {{0.98}{0.95}{0.90}{0.75}{0.5}};
    }

    return grid;
}


//------------------------------------------------------------------------------------------------------------------------

lfunction absrel.ComputeOnAGrid (grid_definition, lfname) {

    parameter_names = utility.Keys (grid_definition);
    parameter_count = Abs (grid_definition);
    grid_dimensions = {};
    total_grid_points = 1;

    utility.ForEachPair (grid_definition, "_key_", "_value_",
    '
        `&grid_dimensions`[_key_] = utility.Array1D (_value_);
        `&total_grid_points` = `&total_grid_points` * `&grid_dimensions`[_key_];
    ');


    best_val :> -1e100;
    best_val = -1e100;


    LFCompute (^lfname,LF_START_COMPUTE);


    for (grid_point = 0; grid_point < total_grid_points; grid_point += 1) {
        index = grid_point;

        current_state = grid_dimensions;

        for (p_id = 0; p_id < parameter_count; p_id += 1) {
            p_name = parameter_names[p_id];
            current_state[p_name] = (grid_definition[p_name])[index % grid_dimensions[p_name]];
            index = index $ grid_dimensions[p_name];
        }

        absrel.SetValues (current_state);

        LFCompute (^lfname, try_value);

        if (try_value > best_val) {
            best_state  = current_state;
            best_val = try_value;
        }
    }

    absrel.SetValues (best_state);
    LFCompute(^lfname,LF_DONE_COMPUTE);

    return best_state;

}

function absrel.SetValues(set) {
    if (Type (set) == "AssociativeList") {
        utility.ForEachPair (set, "_key_", "_value_",
        '
            parameters.SetValue (_key_, _value_);
        ');
    }
}

//----------------------------------------------------
lfunction absrel.get_tree_name (lf_id) {
    GetString (info, ^lf_id, -1);
    return (info["Trees"])[0];
}

lfunction absrel.get_model_id (lf_id) {
    GetString (info, ^lf_id, -1);
    return (info["Models"])[0];
}

function absrel.constrain_everything (lf_id) {
    GetString (absrel.constrain_everything.info, ^lf_id, -1);

    utility.ForEach (absrel.constrain_everything.info ["Global Independent"], "_value_",
                     "parameters.SetConstraint (_value_, Eval (_value_), terms.global)");
    utility.ForEach (absrel.constrain_everything.info ["Local Independent"], "_value_",
                     "parameters.SetConstraint (_value_, Eval (_value_), '')");
}

lfunction absrel.local.omega(branch_info) {
    return parameters.NormalizeRatio ((branch_info[utility.getGlobalValue ("terms.parameters.nonsynonymous_rate")])[utility.getGlobalValue("terms.fit.MLE")],
                                      (branch_info[utility.getGlobalValue ("terms.parameters.synonymous_rate")])[utility.getGlobalValue("terms.fit.MLE")]);
}

//------------------------------------------------------------------------------

lfunction absrel.BS_REL.ModelDescription (type, code, components) {
    model = models.codon.BS_REL.ModelDescription(type, code, components);
    model [utility.getGlobalValue("terms.model.defineQ")] = "absrel.BS_REL._DefineQ";
    return model;
}



//------------------------------------------------------------------------------

lfunction absrel.BS_REL._GenerateRate (fromChar, toChar, namespace, model_type, _tt, alpha, alpha_term, beta, beta_term, omega, omega_term) {

    p = {};
    diff = models.codon.diff(fromChar, toChar);

    if (None != diff) {
        p[model_type] = {};
        p[utility.getGlobalValue("terms.global")] = {};

        if (diff[utility.getGlobalValue("terms.diff.from")] > diff[utility.getGlobalValue("terms.diff.to")]) {
            nuc_rate = "theta_" + diff[utility.getGlobalValue("terms.diff.to")] + diff[utility.getGlobalValue("terms.diff.from")];
        } else {
            nuc_rate = "theta_" + diff[utility.getGlobalValue("terms.diff.from")] + diff[utility.getGlobalValue("terms.diff.to")];
        }
        nuc_rate = parameters.ApplyNameSpace(nuc_rate, namespace);
        (p[utility.getGlobalValue("terms.global")])[terms.nucleotideRate(diff[utility.getGlobalValue("terms.diff.from")], diff[utility.getGlobalValue("terms.diff.to")])] = nuc_rate;

        if (_tt[fromChar] != _tt[toChar]) {
            if (model_type == utility.getGlobalValue("terms.global")) {
                aa_rate = parameters.ApplyNameSpace(omega, namespace);
                (p[model_type])[omega_term] = aa_rate;
            } else {
                aa_rate = omega + "*" + alpha;
                (p[model_type])[omega_term] = omega;
            }
            p[utility.getGlobalValue("terms.model.rate_entry")] = nuc_rate + "*" + aa_rate;
        } else {
            if (model_type == utility.getGlobalValue("terms.local")) {
                (p[model_type])[alpha_term] = alpha;
                p[utility.getGlobalValue("terms.model.rate_entry")] = nuc_rate + "*" + alpha;
            } else {
                p[utility.getGlobalValue("terms.model.rate_entry")] = nuc_rate;
            }
        }
    }


    return p;
}

//------------------------------------------------------------------------------

lfunction absrel.BS_REL._DefineQ(bs_rel, namespace) {
    rate_matrices = {};

    bs_rel [utility.getGlobalValue("terms.model.q_ij")] = &rate_generator;
    bs_rel [utility.getGlobalValue("terms.mixture.mixture_components")] = {};

    _aux = parameters.GenerateSequentialNames ("bsrel_mixture_aux", bs_rel[utility.getGlobalValue("terms.model.components")] - 1, "_");
    _wts = parameters.helper.stick_breaking (_aux, None);
    mixture = {};

    component_count = bs_rel[utility.getGlobalValue("terms.model.components")];

    for (component = 1; component <= component_count; component += 1) {
       key = "component_" + component;
       ExecuteCommands ("
        function rate_generator (fromChar, toChar, namespace, model_type, _tt) {
           return absrel.BS_REL._GenerateRate (fromChar, toChar, namespace, model_type, _tt,
                'alpha', utility.getGlobalValue('terms.parameters.synonymous_rate'),
                'beta_`component`', terms.AddCategory (utility.getGlobalValue('terms.parameters.nonsynonymous_rate'), component),
                'omega`component`', terms.AddCategory (utility.getGlobalValue('terms.parameters.omega_ratio'), component));
            }"
       );

       if ( component < component_count) {
            model.generic.AddLocal ( bs_rel, _aux[component-1], terms.AddCategory (utility.getGlobalValue("terms.mixture.mixture_aux_weight"), component ));
            parameters.SetRange (_aux[component-1], utility.getGlobalValue("terms.range_almost_01"));
       }

       models.codon.generic.DefineQMatrix(bs_rel, namespace);
       rate_matrices [key] = bs_rel[utility.getGlobalValue("terms.model.rate_matrix")];
       (bs_rel [^'terms.mixture.mixture_components'])[key] = _wts [component-1];
    }


    bs_rel[utility.getGlobalValue("terms.model.rate_matrix")] = rate_matrices;
    parameters.SetConstraint(((bs_rel[utility.getGlobalValue("terms.parameters")])[utility.getGlobalValue("terms.global")])[terms.nucleotideRate("A", "G")], "1", "");
    return bs_rel;
}

return 0;

io.ReportProgressMessageMD("RELAX", "codon-refit", "* " + selection.io.report_fit (relax.final_partitioned_mg_results, 0, relax.codon_data_info[terms.data.sample_size]));

relax.global_dnds  = selection.io.extract_global_MLE_re (relax.final_partitioned_mg_results, "^" + terms.parameters.omega_ratio);
relax.report_dnds = {};

utility.ForEach (relax.global_dnds, "_value_", '
    io.ReportProgressMessageMD ("RELAX", "codon-refit", "* " + _value_[terms.description] + " = " + Format (_value_[terms.fit.MLE],8,4));
    relax.report_dnds [(regexp.FindSubexpressions (_value_[terms.description], "^" + terms.parameters.omega_ratio + ".+\\*(.+)\\*$"))[1]] = {"0" : {terms.json.omega_ratio : _value_[terms.fit.MLE], terms.json.proportion : 1}};
');

selection.io.json_store_branch_attribute(relax.json, terms.original_name, terms.json.node_label, 0,
                                         0,
                                         relax.name_mapping);


selection.io.json_store_lf_spool (relax.codon_data_info [terms.json.json], relax.json,
                            relax.MG94,
                            relax.final_partitioned_mg_results[terms.fit.log_likelihood],
                            relax.final_partitioned_mg_results[terms.parameters] ,
                            math.GetIC (relax.final_partitioned_mg_results[terms.fit.log_likelihood], relax.final_partitioned_mg_results[terms.parameters], relax.codon_data_info[terms.data.sample_size]),
                            relax.report_dnds);


selection.io.stopTimer (relax.json [terms.json.timers], "Preliminary model fitting");


if (relax.model_set == "All") { // run all the models

    relax.ge.bsrel_model =  model.generic.DefineMixtureModel("relax.BS_REL.ModelDescription",
            "relax.ge", {
                "0": parameters.Quote(terms.local),
                "1": relax.codon_data_info[terms.code],
                "2": parameters.Quote (relax.rate_classes) // the number of rate classes
            },
            relax.filter_names,
            None);

    for (relax.i = 1; relax.i < relax.rate_classes; relax.i += 1) {
        parameters.SetRange (model.generic.GetGlobalParameter (relax.ge.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.i)), terms.range_almost_01);
    }
    parameters.SetRange (model.generic.GetGlobalParameter (relax.ge.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.rate_classes)), terms.range_gte1);

    relax.model_object_map = { "relax.ge" :       relax.ge.bsrel_model };

    io.ReportProgressMessageMD ("RELAX", "gd", "Fitting the general descriptive (separate k per branch) model");
    selection.io.startTimer (relax.json [terms.json.timers], "General descriptive model fitting", 2);

    relax.ge_guess = relax.DistributionGuess(utility.Map (selection.io.extract_global_MLE_re (relax.final_partitioned_mg_results, "^" + terms.parameters.omega_ratio + ".+test.+"), "_value_",
            "_value_[terms.fit.MLE]"));

    relax.distribution = models.codon.BS_REL.ExtractMixtureDistribution(relax.ge.bsrel_model);
    parameters.SetStickBreakingDistribution (relax.distribution, relax.ge_guess);

    relax.general_descriptive.fit =  estimators.FitLF (relax.filter_names,
                                        relax.trees,
                                        { "0" : {"DEFAULT" : "relax.ge"}},
                                        relax.final_partitioned_mg_results,
                                        relax.model_object_map,
                                        {
                                            terms.run_options.apply_user_constraints: "relax.init.k"
                                        });



    selection.io.stopTimer (relax.json [terms.json.timers], "General descriptive model fitting");

    io.ReportProgressMessageMD("RELAX", "ge", "* " + selection.io.report_fit (relax.general_descriptive.fit, 9, relax.codon_data_info[terms.data.sample_size]));
    io.ReportProgressMessageMD("RELAX", "ge", "* The following baseline rate distribution for branch-site combinations was inferred");
    relax.inferred_ge_distribution = parameters.GetStickBreakingDistribution (models.codon.BS_REL.ExtractMixtureDistributionFromFit (relax.ge.bsrel_model, relax.general_descriptive.fit)) % 0;
    selection.io.report_dnds (relax.inferred_ge_distribution);
    relax.distribution_for_json = {'Shared' : utility.Map (utility.Range (relax.rate_classes, 0, 1),
                                                         "_index_",
                                                         "{terms.json.omega_ratio : relax.inferred_ge_distribution [_index_][0],
                                                           terms.json.proportion  : relax.inferred_ge_distribution [_index_][1]}")
                                   };
    selection.io.json_store_lf_spool (relax.codon_data_info [terms.json.json], relax.json,
                                "General descriptive",
                                relax.general_descriptive.fit[terms.fit.log_likelihood],
                                relax.general_descriptive.fit[terms.parameters] + 9 , // +9 comes from CF3x4
                                math.GetIC (relax.general_descriptive.fit[terms.fit.log_likelihood], relax.general_descriptive.fit[terms.parameters] + 9, relax.codon_data_info[terms.data.sample_size]),
                                relax.distribution_for_json
                            );

    selection.io.json_store_branch_attribute(relax.json, "General descriptive", terms.branch_length, 1,
                                                 0,
                                                 selection.io.extract_branch_info((relax.general_descriptive.fit[terms.branch_length])[0], "selection.io.branch.length"));

    relax.k_estimates = selection.io.extract_branch_info((relax.general_descriptive.fit[terms.branch_length])[0], "relax.extract.k");

    relax.k_stats = math.GatherDescriptiveStats (utility.Map (utility.Values (relax.k_estimates), "_value_", "0+_value_"));

    io.ReportProgressMessageMD("RELAX", "ge", "* Branch-level `terms.relax.k` distribution has mean " + Format (relax.k_stats[terms.math.mean], 5,2) + ", median " +
                                                 Format (relax.k_stats[terms.math.median], 5,2) + ", and 95% of the weight in " + Format (relax.k_stats[terms.math._2.5], 5,2) + " - " + Format (relax.k_stats[terms.math._97.5], 5,2));


    selection.io.json_store_branch_attribute(relax.json, "k (general descriptive)", terms.json.branch_label, 1,
                                                 0,
                                                 relax.k_estimates);

} else {
    relax.general_descriptive.fit = relax.final_partitioned_mg_results;
}

/* now fit the two main models for RELAX */

io.ReportProgressMessageMD ("RELAX", "alt", "Fitting the alternative model to test K != 1");

selection.io.startTimer (relax.json [terms.json.timers], "RELAX alternative model fitting", 3);

relax.test.bsrel_model =  model.generic.DefineMixtureModel("models.codon.BS_REL.ModelDescription",
        "relax.test", {
            "0": parameters.Quote(terms.global),
            "1": relax.codon_data_info[terms.code],
            "2": parameters.Quote (relax.rate_classes) // the number of rate classes
        },
        relax.filter_names,
        None);



relax.reference.bsrel_model =  model.generic.DefineMixtureModel("models.codon.BS_REL.ModelDescription",
        "relax.reference", {
            "0": parameters.Quote(terms.global),
            "1": relax.codon_data_info[terms.code],
            "2": parameters.Quote (relax.rate_classes) // the number of rate classes
        },
        relax.filter_names,
        None);

relax.bound_weights = models.BindGlobalParameters ({"0" : relax.test.bsrel_model, "1" : relax.reference.bsrel_model}, terms.mixture.mixture_aux_weight + ".+");

models.BindGlobalParameters ({"0" : relax.test.bsrel_model, "1" : relax.reference.bsrel_model}, terms.nucleotideRate("[ACGT]","[ACGT]"));

parameters.DeclareGlobalWithRanges (relax.relaxation_parameter, 1, 0, 50);
model.generic.AddGlobal (relax.test.bsrel_model, relax.relaxation_parameter, terms.relax.k);

for (relax.i = 1; relax.i < relax.rate_classes; relax.i += 1) {
    parameters.SetRange (model.generic.GetGlobalParameter (relax.reference.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.i)), terms.range01);
    parameters.SetRange (model.generic.GetGlobalParameter (relax.test.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.i)), terms.range01);
    parameters.SetConstraint (model.generic.GetGlobalParameter (relax.test.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.i)),
                              model.generic.GetGlobalParameter (relax.reference.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.i)) + "^" + relax.relaxation_parameter,
                              terms.global);
}
parameters.SetRange (model.generic.GetGlobalParameter (relax.reference.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.rate_classes)), terms.range_gte1);
parameters.SetRange (model.generic.GetGlobalParameter (relax.test.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.rate_classes)), terms.range_gte1);
parameters.SetConstraint (model.generic.GetGlobalParameter (relax.test.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.i)),
                          model.generic.GetGlobalParameter (relax.reference.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.i)) + "^" + relax.relaxation_parameter,
                          terms.global);

relax.model_map = {
                    "relax.test" : utility.Filter (relax.selected_branches[0], '_value_', '_value_ == relax.test_branches_name'),
                    "relax.reference" : utility.Filter (relax.selected_branches[0], '_value_', '_value_ == relax.reference_branches_name')
                  };


// constrain the proportions to be the same

relax.model_object_map = { "relax.reference" : relax.reference.bsrel_model,
                            "relax.test" :       relax.test.bsrel_model };

if (relax.model_set != "All") {
    relax.ge_guess = relax.DistributionGuess(utility.Map (selection.io.extract_global_MLE_re (relax.final_partitioned_mg_results, "^" + terms.parameters.omega_ratio + ".+test.+"), "_value_",
            "_value_[terms.fit.MLE]"));

    relax.distribution = models.codon.BS_REL.ExtractMixtureDistribution(relax.reference.bsrel_model);
    parameters.SetStickBreakingDistribution (relax.distribution, relax.ge_guess);
}

if (relax.has_unclassified) {
    relax.unclassified.bsrel_model =  model.generic.DefineMixtureModel("models.codon.BS_REL.ModelDescription",
        "relax.unclassified", {
            "0": parameters.Quote(terms.global),
            "1": relax.codon_data_info[terms.code],
            "2": parameters.Quote (relax.rate_classes) // the number of rate classes
        },
        relax.filter_names,
        None);

    for (relax.i = 1; relax.i < relax.rate_classes-1; relax.i += 1) {
        parameters.SetRange (model.generic.GetGlobalParameter (relax.unclassified.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.i)), terms.range01);
    }

    parameters.SetRange (model.generic.GetGlobalParameter (relax.unclassified.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.rate_classes)), terms.range_gte1);

    relax.model_object_map ["relax.unclassified"] = relax.unclassified.bsrel_model;
    relax.model_map ["relax.unclassified"] = utility.Filter (relax.selected_branches[0], '_value_', '_value_ == relax.unclassified_branches_name');
    models.BindGlobalParameters ({"0" : relax.unclassified.bsrel_model, "1" : relax.reference.bsrel_model}, terms.nucleotideRate("[ACGT]","[ACGT]"));
}

relax.alternative_model.fit =  estimators.FitLF (relax.filter_names, relax.trees, { "0" : relax.model_map}, relax.general_descriptive.fit, relax.model_object_map, {terms.run_options.retain_lf_object: TRUE});

io.ReportProgressMessageMD("RELAX", "alt", "* " + selection.io.report_fit (relax.alternative_model.fit, 9, relax.codon_data_info[terms.data.sample_size]));


relax.fitted.K = estimators.GetGlobalMLE (relax.alternative_model.fit,terms.relax.k);
io.ReportProgressMessageMD("RELAX", "alt", "* Relaxation/intensification parameter (K) = " + Format(relax.fitted.K,8,2));
io.ReportProgressMessageMD("RELAX", "alt", "* The following rate distribution was inferred for **test** branches");
relax.inferred_distribution = parameters.GetStickBreakingDistribution (models.codon.BS_REL.ExtractMixtureDistribution (relax.test.bsrel_model)) % 0;
selection.io.report_dnds (relax.inferred_distribution);

io.ReportProgressMessageMD("RELAX", "alt", "* The following rate distribution was inferred for **reference** branches");
relax.inferred_distribution_ref = parameters.GetStickBreakingDistribution (models.codon.BS_REL.ExtractMixtureDistribution (relax.reference.bsrel_model)) % 0;
selection.io.report_dnds (relax.inferred_distribution_ref);

relax.distribution_for_json = {relax.test_branches_name : utility.Map (utility.Range (relax.rate_classes, 0, 1),
                                                     "_index_",
                                                     "{terms.json.omega_ratio : relax.inferred_distribution [_index_][0],
                                                       terms.json.proportion  : relax.inferred_distribution [_index_][1]}"),

                                relax.reference_branches_name : utility.Map (utility.Range (relax.rate_classes, 0, 1),
                                                     "_index_",
                                                     "{terms.json.omega_ratio : relax.inferred_distribution_ref [_index_][0],
                                                       terms.json.proportion  : relax.inferred_distribution_ref [_index_][1]}")
                               };

selection.io.json_store_lf_spool (relax.codon_data_info [terms.json.json], relax.json,
                            "RELAX alternative",
                            relax.alternative_model.fit[terms.fit.log_likelihood],
                            relax.alternative_model.fit[terms.parameters] + 9 , // +9 comes from CF3x4
                            relax.codon_data_info[terms.data.sample_size],
                            relax.distribution_for_json
                        );

selection.io.json_store_branch_attribute(relax.json, "RELAX alternative", terms.branch_length, 2,
                                             0,
                                             selection.io.extract_branch_info((relax.alternative_model.fit[terms.branch_length])[0], "selection.io.branch.length"));

selection.io.stopTimer (relax.json [terms.json.timers], "RELAX alternative model fitting");

// NULL MODEL

selection.io.startTimer (relax.json [terms.json.timers], "RELAX null model fitting", 4);

io.ReportProgressMessageMD ("RELAX", "null", "Fitting the null (K := 1) model");
parameters.SetConstraint (model.generic.GetGlobalParameter (relax.test.bsrel_model , terms.relax.k), terms.parameters.one, terms.global);
relax.null_model.fit = estimators.FitExistingLF (relax.alternative_model.fit[terms.likelihood_function], relax.model_object_map);
io.ReportProgressMessageMD ("RELAX", "null", "* " + selection.io.report_fit (relax.null_model.fit, 9, relax.codon_data_info[terms.data.sample_size]));
relax.LRT = math.DoLRT (relax.null_model.fit[terms.fit.log_likelihood], relax.alternative_model.fit[terms.fit.log_likelihood], 1);


io.ReportProgressMessageMD("RELAX", "null", "* The following rate distribution for test/reference branches was inferred");
relax.inferred_distribution = parameters.GetStickBreakingDistribution (models.codon.BS_REL.ExtractMixtureDistributionFromFit (relax.test.bsrel_model, relax.null_model.fit)) % 0;
selection.io.report_dnds (relax.inferred_distribution);

relax.distribution_for_json = {relax.test_branches_name : utility.Map (utility.Range (relax.rate_classes, 0, 1),
                                                     "_index_",
                                                     "{terms.json.omega_ratio : relax.inferred_distribution [_index_][0],
                                                       terms.json.proportion  : relax.inferred_distribution [_index_][1]}")};

relax.distribution_for_json   [relax.reference_branches_name] =   relax.distribution_for_json   [relax.test_branches_name];

selection.io.json_store_lf_spool (relax.codon_data_info [terms.json.json], relax.json,
                            "RELAX null",
                            relax.null_model.fit[terms.fit.log_likelihood],
                            relax.null_model.fit[terms.parameters] + 9 , // +9 comes from CF3x4
                            relax.codon_data_info[terms.data.sample_size],
                            relax.distribution_for_json
                        );

selection.io.json_store_branch_attribute(relax.json, "RELAX null", terms.branch_length, 3,
                                             0,
                                             selection.io.extract_branch_info((relax.null_model.fit[terms.branch_length])[0], "selection.io.branch.length"));


console.log ("----\n## Test for relaxation (or intensification) of selection [RELAX]");
console.log ( "Likelihood ratio test **p = " + Format (relax.LRT[terms.p_value], 8, 4) + "**.");

if (relax.LRT[terms.p_value] <= relax.p_threshold) {
    if (relax.fitted.K > 1) {
        console.log (">Evidence for relaxation of selection among **test** branches _relative_ to the **reference** branches at P<="+ relax.p_threshold);
    } else {
        console.log (">Evidence for intensification of selection among **test** branches _relative_ to the **reference** branches at P<="+ relax.p_threshold);
    }
} else {
    console.log (">No significant evidence for relaxation (or intensification) of selection among **test** branches _relative_ to the **reference** branches at P<="+ relax.p_threshold);
}

relax.json [terms.json.test_results] = relax.LRT;
(relax.json [terms.json.test_results])[terms.relax.k] = relax.fitted.K;

console.log ("----\n");

selection.io.stopTimer (relax.json [terms.json.timers], "RELAX null model fitting");

if (relax.model_set == "All") {
    selection.io.startTimer (relax.json [terms.json.timers], "RELAX partitioned exploratory", 5);

    io.ReportProgressMessageMD ("RELAX", "pe", "Fitting the partitioned exploratory model (separate distributions for *test* and *reference* branches)");
    parameters.RemoveConstraint (utility.Keys (relax.bound_weights));
    for (relax.i = 1; relax.i < relax.rate_classes; relax.i += 1) {
        parameters.RemoveConstraint (model.generic.GetGlobalParameter (relax.test.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,relax.i)));
    }
    relax.pe.fit = estimators.FitExistingLF (relax.alternative_model.fit[terms.likelihood_function], relax.model_object_map);
    io.ReportProgressMessageMD ("RELAX", "pe", "* " + selection.io.report_fit (relax.pe.fit, 9, relax.codon_data_info[terms.data.sample_size]));
    io.ReportProgressMessageMD ("RELAX", "pe", "* The following rate distribution was inferred for *test* branches ");
    relax.test.inferred_distribution = parameters.GetStickBreakingDistribution (models.codon.BS_REL.ExtractMixtureDistribution(relax.test.bsrel_model)) % 0;
    selection.io.report_dnds (relax.test.inferred_distribution);
    io.ReportProgressMessageMD("RELAX", "pe", "* The following rate distribution was inferred for *reference* branches ");
    relax.reference.inferred_distribution =  parameters.GetStickBreakingDistribution (models.codon.BS_REL.ExtractMixtureDistribution(relax.reference.bsrel_model)) % 0;
    selection.io.report_dnds (relax.reference.inferred_distribution);

    relax.distribution_for_json = {relax.test_branches_name : utility.Map (utility.Range (relax.rate_classes, 0, 1),
                                                         "_index_",
                                                         "{terms.json.omega_ratio : relax.test.inferred_distribution [_index_][0],
                                                           terms.json.proportion  : relax.test.inferred_distribution [_index_][1]}"),

                                    relax.reference_branches_name : utility.Map (utility.Range (relax.rate_classes, 0, 1),
                                                         "_index_",
                                                         "{terms.json.omega_ratio : relax.reference.inferred_distribution [_index_][0],
                                                           terms.json.proportion  : relax.reference.inferred_distribution [_index_][1]}")
                                   };

    selection.io.json_store_lf_spool (relax.codon_data_info [terms.json.json], relax.json,
                                "RELAX partitioned exploratory",
                                relax.pe.fit[terms.fit.log_likelihood],
                                relax.pe.fit[terms.parameters] + 9 , // +9 comes from CF3x4
                                relax.codon_data_info[terms.data.sample_size],
                                relax.distribution_for_json
                            );

    selection.io.json_store_branch_attribute(relax.json, "RELAX partitioned exploratory", terms.branch_length, 4,
                                                 0,
                                                 selection.io.extract_branch_info((relax.pe.fit[terms.branch_length])[0], "selection.io.branch.length"));


    selection.io.stopTimer (relax.json [terms.json.timers], "RELAX partitioned exploratory");
}

selection.io.stopTimer (relax.json [terms.json.timers], "Overall");
io.SpoolJSON (relax.json, relax.codon_data_info [terms.json.json]);

return relax.json;


//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------

lfunction relax.extract.k(branch_info) {
    return (branch_info[utility.getGlobalValue("terms.relax.k")])[utility.getGlobalValue("terms.fit.MLE")];
}

//------------------------------------------------------------------------------

lfunction relax.set.k (tree_name, node_name, model_description) {
    if (utility.Has (model_description [utility.getGlobalValue ("terms.local")], utility.getGlobalValue ("terms.relax.k"), "String")) {
        k = (model_description [utility.getGlobalValue ("terms.local")])[utility.getGlobalValue ("terms.relax.k")];
        parameters.SetValue (tree_name + "." + node_name + "." + k, 1);
        parameters.SetRange (tree_name + "." + node_name + "." + k, utility.getGlobalValue ("terms.relax.k_range"));
    }
    return tree_name + "." + node_name + "." + k;
}

//------------------------------------------------------------------------------

lfunction relax.init.k (lf_id, components, data_filter, tree, model_map, initial_values, model_objects) {
    parameter_set = estimators.TraverseLocalParameters (lf_id, model_objects, "relax.set.k");
    parameters.SetConstraint (model.generic.GetGlobalParameter (utility.getGlobalValue("relax.ge.bsrel_model") , terms.AddCategory (utility.getGlobalValue("terms.parameters.omega_ratio"),2)), utility.getGlobalValue("terms.parameters.one"), utility.getGlobalValue("terms.global"));
    /*parameters.SetConstraint (model.generic.GetGlobalParameter (utility.getGlobalValue("relax.ge.bsrel_model") , terms.AddCategory (utility.getGlobalValue("terms.parameters.omega_ratio"),utility.getGlobalValue ("relax.rate_classes"))),
                             "1/(" +
                                Join ("*", utility.Map (
                                    utility.Range (utility.getGlobalValue ("relax.rate_classes") - 1, 1, 1),
                                    "_value_",
                                    'model.generic.GetGlobalParameter (relax.ge.bsrel_model , terms.AddCategory (terms.parameters.omega_ratio,_value_))'
                                    ))
                             + ")",
                            "global");*/

    return 0;
}

//------------------------------------------------------------------------------


lfunction relax.DistributionGuess (mean) {
    guess = {{0.05,0.7}{0.25,0.2}{10,0.1}};

    norm = + guess[-1][1];
    guess_mean = 1/(+(guess [-1][0] $ guess [-1][1]))/norm;
    return guess["_MATRIX_ELEMENT_VALUE_*(guess_mean*(_MATRIX_ELEMENT_COLUMN_==0)+(_MATRIX_ELEMENT_COLUMN_==1)*(1/norm))"];
}


//------------------------------------------------------------------------------
lfunction relax.select_branches(partition_info) {

    io.CheckAssertion("utility.Array1D (`&partition_info`) == 1", "RELAX only works on a single partition dataset");
    available_models = {};
    branch_set = {};


    tree_for_analysis = (partition_info[0])[utility.getGlobalValue("terms.data.tree")];
    utility.ForEach (tree_for_analysis[utility.getGlobalValue("terms.trees.model_map")], "_value_", "`&available_models`[_value_] += 1");
    list_models   = utility.Keys   (available_models); // get keys
    branch_counts = utility.Values (available_models);
    option_count  = Abs (available_models);

    io.CheckAssertion("`&option_count` >= 2", "RELAX requires at least one designated set of branches in the tree.");

    selectTheseForTesting = {
        option_count, 2
    };

    for (k = 0; k < option_count; k += 1) {
        if (list_models[k] != "") {
            selectTheseForTesting[k][0] = list_models[k];
            selectTheseForTesting[k][1] = "Set " + list_models[k] + " with " + available_models[list_models[k]] + " branches";
        } else {
            selectTheseForTesting[k][0] = "Unlabeled branches";
            selectTheseForTesting[k][1] = "Set of " + available_models[list_models[k]] + " unlabeled branches";
        }
    }

    ChoiceList(testSet, "Choose the set of branches to use as the _test_ set", 1, NO_SKIP, selectTheseForTesting);
    io.CheckAssertion ("`&testSet` >= 0", "User cancelled branch selection; analysis terminating");
    if (option_count > 2) {
        ChoiceList(referenceSet, "Choose the set of branches to use as the _reference_ set", 1, testSet, selectTheseForTesting);
        io.CheckAssertion ("`&referenceSet` >= 0", "User cancelled branch selection; analysis terminating");
    } else {
        referenceSet = 1-testSet;
    }

    return_set = {};

    tree_configuration = {};
    tree_for_analysis = (partition_info[0])[utility.getGlobalValue("terms.data.tree")];

    tag_test = selectTheseForTesting [testSet][0];
    if (tag_test == "Unlabeled branches") {
        tag_test = "";
    }
    tag_reference = selectTheseForTesting [referenceSet][0];
    if (tag_reference == "Unlabeled branches") {
        tag_reference = "";
    }

    utility.ForEachPair (tree_for_analysis[utility.getGlobalValue("terms.trees.model_map")], "_key_", "_value_", "
        if (`&tag_test` == _value_ ) {
            `&tree_configuration`[_key_] = utility.getGlobalValue('relax.test_branches_name');
        } else {
            if (`&tag_reference` == _value_ ) {
                `&tree_configuration`[_key_] = utility.getGlobalValue('relax.reference_branches_name');
            } else {
                `&tree_configuration`[_key_] = utility.getGlobalValue('relax.unclassified_branches_name');
            }
        }
    ");

    return_set + tree_configuration;
    return return_set;
}
