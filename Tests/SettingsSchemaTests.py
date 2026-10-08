"""Validate the UI/config contract without requiring Apple's Preferences runtime."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parents[1]
items = plistlib.loads((root / 'Preferences/Resources/Visualizer.plist').read_bytes())['items']
loader = (root / 'Visualization/ULPVisualPreferences.m').read_text()
read_keys = set(re.findall(r'(?:NUMBER|BOOLEAN)\(\w+, "([^"]+)"\)', loader))
read_keys.update(re.findall(r'ULP(?:Number|Bool|Byte)\(values, @"([^"]+)"', loader))
read_keys.add('VisualColor')
for resource in ('Visualizer', 'Root'):
    resource_items = plistlib.loads((root / f'Preferences/Resources/{resource}.plist').read_bytes())['items']
    for item in resource_items:
        if item['cell'] == 'PSButtonCell':
            assert item.get('buttonAction'), f'Missing PSButtonCell callback: {item}'
            assert 'action' not in item, f'Generic action does not dispatch button taps: {item}'
for mode in range(9):
    visible = [item for item in items if 'ulpModes' not in item or mode in item['ulpModes']]
    keys = [item['key'] for item in visible if 'key' in item]
    assert len(keys) == len(set(keys)), f'Duplicate setting in mode {mode}'
    for item in visible:
        if 'key' in item:
            assert item['key'] in read_keys, f'Unimplemented setting: {item["key"]}'
        for dependency in ('ulpDependsOn', 'ulpDisabledBy'):
            if dependency in item:
                assert item[dependency] in keys, f'Missing source: {mode} {item}'
        if item['cell'] == 'PSSliderCell':
            assert item['min'] <= item['default'] <= item['max'], item
        if item['cell'] == 'PSLinkListCell':
            assert len(item['validTitles']) == len(item['validValues']), item
            assert item['default'] in item['validValues'], item
    assert 'VisualPreset' not in keys, 'Legacy presets must not override the chosen mode'
print('SettingsSchemaTests OK: 9 mode configurations')
