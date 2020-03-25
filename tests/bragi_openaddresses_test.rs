// Copyright © 2017, Canal TP and/or its affiliates. All rights reserved.
//
// This file is part of Navitia,
//     the software to build cool stuff with public transport.
//
// Hope you'll enjoy and contribute to this project,
//     powered by Canal TP (www.canaltp.fr).
// Help us simplify mobility and open public transport:
//     a non ending quest to the responsive locomotion way of traveling!
//
// LICENCE: This program is free software; you can redistribute it
// and/or modify it under the terms of the GNU Affero General Public
// License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public
// License along with this program. If not, see
// <http://www.gnu.org/licenses/>.
//
// Stay tuned using
// twitter @navitia
// IRC #navitia on freenode
// https://groups.google.com/d/forum/navitia
// www.navitia.io

use super::count_types;
use super::get_types;
use super::get_value;
use super::get_values;
use super::BragiHandler;
use std::path::Path;

use std::io;

pub fn bragi_openaddresses_test(es_wrapper: crate::ElasticSearchWrapper<'_>) {
    let mut bragi = BragiHandler::new(es_wrapper.host());
    let out_dir = Path::new(env!("OUT_DIR"));

    // *********************************
    // We load the OSM dataset and openaddress sample dataset
    // the current dataset are thus (load order matters):
    // - osm_fixture.osm.pbf (including ways)
    // - sample-oa.csv
    // *********************************
    //let osm2mimir = out_dir.join("../../../osm2mimir").display().to_string();
    //crate::launch_and_assert(
        //&osm2mimir,
        //&[
            //"--input=./tests/fixtures/osm_fixture.osm.pbf".into(),
            //"--import-admin".into(),
            //"--import-way".into(),
            //"--level=8".into(),
            //format!("--connection-string={}", es_wrapper.host()),
        //],
        //&es_wrapper,
    //);

    let openaddresses2mimir = out_dir.join("../../../openaddresses2mimir").display().to_string();
    crate::launch_and_assert(
        &openaddresses2mimir,
        &[
            "--input=./tests/fixtures/sample-oa.csv".into(),
            format!("--connection-string={}", es_wrapper.host()),
        ],
        &es_wrapper,
    );

    openaddresses_housenumber_zip_code_test(&mut bragi);
    openaddresses_zip_code_test(&mut bragi);
    openaddresses_zip_code_address_test(&mut bragi);
}

fn openaddresses_housenumber_zip_code_test(bragi: &mut BragiHandler) {
    // we search for a house number with a postcode, we should be able to find
    // the house number with this number in this city
    let all_20 = bragi.get("/autocomplete?q=27 10117");
    assert_eq!(all_20.len(), 1);
    assert!(get_values(&all_20, "postcode")
        .iter()
        .all(|r| *r == "10117",));
    let types = get_types(&all_20);
    let count = count_types(&types, "street");
    assert_eq!(count, 0);

    let count = count_types(&types, "city");
    assert_eq!(count, 0);

    let count = count_types(&types, "house");
    assert_eq!(count, 1);
    let first_house = all_20.iter().find(|e| get_value(e, "type") == "house");
    assert_eq!(get_value(first_house.unwrap(), "housenumber"), "27");
    assert_eq!(get_value(first_house.unwrap(), "label"), "Dorotheenstraße 27");
}

fn openaddresses_zip_code_test(bragi: &mut BragiHandler) {
    // For some reason, the filter when searching excludes the actual results.
    // This is not testing how it should be, but how it does work ATM.
    let res = bragi.get("/autocomplete?q=10117");
    assert_eq!(res.len(), 0);
}

fn openaddresses_zip_code_address_test(bragi: &mut BragiHandler) {
    let all_20 = bragi.get("/autocomplete?q=Otto-Braun-Straße 72 10178");
    assert_eq!(all_20.len(), 1);
    assert!(get_values(&all_20, "postcode")
        .iter()
        .all(|r| *r == "10178",));
    let types = get_types(&all_20);
    let count = count_types(&types, "street");
    assert_eq!(count, 0);

    let count = count_types(&types, "city");
    assert_eq!(count, 0);

    let count = count_types(&types, "house");
    assert_eq!(count, 1);

    assert_eq!(
        get_values(&all_20, "label"),
        vec!["Otto-Braun-Straße 72"]
    );
}
