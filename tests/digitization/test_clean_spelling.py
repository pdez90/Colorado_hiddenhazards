"""Spelling consensus across editions (pipeline/clean_spelling.py): misreadings are voted out, renames and numbers are kept."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'pipeline'))
from clean_spelling import clean_group

def test_letter_vote_repairs_three_different_misreadings():
    got = clean_group(['ESKIMO RADIATOK HFG Co', 'ESKIMO RADIATOR MEG CO', 'ESKIMO RADIATOR MFG CC'], [1966, 1967, 1968])
    assert got == ['ESKIMO RADIATOR MFG CO'] * 3

def test_majority_word_wins():
    got = clean_group(['UNITED STEEL + IRCN WCRKS', 'UNITED STEEL + IRON WORKS', 'UNITED STEEL + IRON WORKS'], [1968, 1970, 1973])
    assert set(got) == {'UNITED STEEL + IRON WORKS'}

def test_rename_is_kept():
    got = clean_group(['SUNLIGHT METAL PRODUCTS CO', 'SUNLIGHT METAL PRODUCTS CO', 'PPG INDUSTRIES INC'], [1965, 1966, 1973])
    assert got[2] == 'PPG INDUSTRIES INC' and got[0] == 'SUNLIGHT METAL PRODUCTS CO'

def test_single_listing_untouched():
    assert clean_group(['MrTOWEST RUBBER + SUPPLY CO'], [1977]) == ['MrTOWEST RUBBER + SUPPLY CO']

def test_two_readings_that_disagree_are_left_alone():
    assert clean_group(['REPUBLIC PRINTING', 'REPUBLIC PRIATING']) == ['REPUBLIC PRINTING', 'REPUBLIC PRIATING']

def test_different_word_counts_never_vote_together_and_untouched_readings_keep_their_case():
    got = clean_group(['Cardiff Publishing', 'CARDIFF PUBLISHING CO', 'CARDIFF PUBLISHING CO', 'CARDIFF PUBLISHING CO'])
    assert got[0] == 'Cardiff Publishing'
    got = clean_group(['319 N CLEVELAND AVE', '319 CLEVELAND AVE', '319 CLEVELAND AVE', '319 CLEVELAND AVE'], digits_must_match=True)
    assert got[0] == '319 N CLEVELAND AVE'

def test_street_numbers_never_change():
    got = clean_group(['12280 W 90TH PL', '12280 W 90TH PL', '12280 W 50TH PL'], [1970, 1973, 1983], digits_must_match=True)
    assert got == ['12280 W 90TH PL', '12280 W 90TH PL', '12280 W 50TH PL']
    got = clean_group(['2295 S CELAWARE ST', '2295 S DELAWARE ST', '2295 S DELAWARE ST'], [1974, 1977, 1980], digits_must_match=True)
    assert set(got) == {'2295 S DELAWARE ST'}

def test_a_different_word_is_not_a_misreading():
    got = clean_group(['MONARCH SHEET METAL MFG CO'] * 4 + ['MONARCH SHEET METAL HEATING CO', 'MCNARCH SHEET METAL MFG CC'])
    assert got[4] == 'MONARCH SHEET METAL HEATING CO' and got[5] == 'MONARCH SHEET METAL MFG CO'

def test_street_directions_are_not_voted():
    got = clean_group(['3516 W TEJON', '3516 N TEJON', '3516 N TEJON', '3516 N TEJCN'], digits_must_match=True)
    assert got == ['3516 W TEJON', '3516 N TEJON', '3516 N TEJON', '3516 N TEJON']
