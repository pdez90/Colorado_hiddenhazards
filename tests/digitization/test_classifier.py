"""sic_classifier / sic_predict: the description -> SIC model learnt from the coded editions. Smoke test: trained on
the golden 1967 and 1977 volumes, it recovers the 2-digit major group of printed 1980 descriptions."""
import pytest
import sic_classifier, sic_predict
from sic_classifier_norm import norm

# (printed SIC, printed description) pairs from the parsed 1980 part 1 edition (work/parsed/DCM_1980_part1.jsonl)
FIXTURES = [
    ('2752', 'COMMERCIAL PRINTING, LITHOGRAPHIC'), ('2711', 'NEWSPAPERS'), ('2751', 'COMMERCIAL PRINTING, LETTERPRESS'),
    ('3599', 'MACHINE SHOP'), ('3444', 'SHEET METAL WORK'), ('2791', 'TYPESETTING'), ('3441', 'FABRICATED STRUCTURAL METAL'),
    ('3272', 'CONCRETE PRODUCTS, NEC'), ('2512', 'UPHOLSTERED HOUSEHOLD FURNITURE'), ('2434', 'WOOD KITCHEN CABINETS'),
    ('2011', 'MEAT PACKING PLANTS'), ('3993', 'SIGNS AND ADVERTISING DISPLAYS'), ('3361', 'ALUMINUM CASTINGS'),
    ('3714', 'MOTOR VEHICLE PARTS AND ACCESSORIES'), ('3079', 'MISCELLANEOUS PLASTICS PRODUCTS'), ('2761', 'BUSINESS FORMS'),
    ('3446', 'ARCHITECTURAL METAL WORK'), ('3469', 'METAL STAMPING'), ('3573', 'ELECTRONIC COMPUTING EQUIPMENT'),
    ('2541', 'COUNTER TOPS'),
]


def test_model_contents(classifier):
    assert set(classifier) == {'vec', 'nn', 'labels', 'docs', 'w'}
    assert len(classifier['docs']) == len(classifier['labels']) == len(classifier['w']) >= 300
    assert all(len(c) == 4 and c.isdigit() for c in classifier['labels'])
    # training descriptions are normalised with sic_classifier.norm, which keeps 'AND' and '&'; queries go through
    # sic_classifier_norm.norm, which drops them (a known asymmetry of the character n-gram model, left as is)
    assert all(d == sic_classifier.norm(d) for d in classifier['docs'])
    assert all(w >= 2 for w in classifier['w'])                        # a description must be printed twice
    assert 'ASTRONOMICAL INSTRUMENTS' not in classifier['docs']        # 1992 (uncoded-era) descriptions are not training data


def test_predict_recovers_major_group(classifier):
    P = sic_predict.predict([d for _, d in FIXTURES])
    assert len(P) == len(FIXTURES)
    hits = sum(c[:2] == pc[:2] for (c, _), (pc, _, _) in zip(FIXTURES, P))
    assert hits / len(FIXTURES) >= 0.70, [(c, d, pc) for (c, d), (pc, _, _) in zip(FIXTURES, P) if c[:2] != pc[:2]]
    exact = sum(c == pc for (c, _), (pc, _, _) in zip(FIXTURES, P))
    assert exact / len(FIXTURES) >= 0.5
    for code, score, doc in P:
        assert len(code) == 4 and 0.0 <= score <= 1.0 + 1e-9 and doc in classifier['docs']


def test_exact_training_description_scores_one(classifier):
    code, score, doc = sic_predict.predict(['SHEET METAL WORK'])[0]
    assert code == '3444' and score == pytest.approx(1.0) and doc == 'SHEET METAL WORK'


def test_norm():
    assert norm('Machine shops, N.E.C.') == 'MACHINE SHOPS'
    assert norm('paints & varnishes and lacquers') == 'PAINTS VARNISHES LACQUERS'
    assert sic_classifier.norm('Food preparations, n e c') == 'FOOD PREPARATIONS'


def test_train_on_empty_glob_gives_no_model(tmp_path):
    with pytest.raises(ValueError):
        sic_classifier.train(str(tmp_path / '*.jsonl'))       # TF-IDF cannot fit an empty vocabulary
