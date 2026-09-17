#!/usr/bin/env python3
"""
Parses the hex-skirmish-game-spec.md and validates traceability index.

Standard library only. No third-party imports, no network, no credentials.
"""

import json
import re
from typing import Dict, List, Tuple, Optional, Any


def parse_sections(text: str) -> List[Dict[str, Any]]:
    """
    Parse spec sections from markdown text.

    Returns list of sections with id, title, start_line, end_line, and text.
    Top-level sections are numbered 1-12; subsections are 1.1, 1.2, etc.
    The document's main title (# ...) is not a section.
    """
    lines = text.split('\n')
    sections = []
    current_section = None

    # Pattern for headings: ## N. Title (top-level) or ### N.M Title (subsection)
    # Top-level: ## N. Title
    # Subsection: ### N.M Title (no period after subsection number)
    section_pattern = re.compile(r'^(##|###)\s+(\d+(?:\.\d+)?)(?:\.)?\s+(.+)$')

    for line_no, line in enumerate(lines, start=1):
        match = section_pattern.match(line)
        if match:
            # Save previous section if it exists
            if current_section is not None:
                current_section['end_line'] = line_no - 1
                current_section['text'] = '\n'.join(
                    lines[current_section['start_line'] - 1:current_section['end_line']]
                )
                sections.append(current_section)

            # Start new section
            section_id = match.group(2)
            title = match.group(3)
            current_section = {
                'id': section_id,
                'title': title,
                'start_line': line_no,
                'end_line': None,
                'text': None
            }

    # Save the last section
    if current_section is not None:
        current_section['end_line'] = len(lines)
        current_section['text'] = '\n'.join(
            lines[current_section['start_line'] - 1:current_section['end_line']]
        )
        sections.append(current_section)

    return sections


def parent_of(section_id: str) -> Optional[str]:
    """
    Return parent section id, or None if this is a top-level section.

    Examples:
      parent_of("7.3") -> "7"
      parent_of("7") -> None
    """
    if '.' in section_id:
        return section_id.split('.')[0]
    return None


def load_index(path: str) -> Tuple[Optional[Dict[str, Any]], List[Dict[str, str]]]:
    """
    Load and validate traceability index from JSON file.

    Returns (parsed_index, errors) where errors is a list of structured error dicts.
    Never raises; returns errors instead.
    """
    errors = []

    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except (IOError, json.JSONDecodeError) as e:
        return None, [{'type': 'parse_error', 'message': str(e)}]

    if not isinstance(data, dict) or 'entries' not in data:
        return None, [{'type': 'schema_error', 'message': 'Index must have "entries" key'}]

    entries = data.get('entries', [])
    if not isinstance(entries, list):
        return None, [{'type': 'schema_error', 'message': '"entries" must be a list'}]

    seen_ids = set()
    seen_active_sections = set()

    for i, entry in enumerate(entries):
        if not isinstance(entry, dict):
            errors.append({'type': 'entry_error', 'index': i, 'message': 'Entry must be a dict'})
            continue

        # Check required fields
        entry_id = entry.get('id')
        section = entry.get('section')
        status = entry.get('status')
        modules = entry.get('modules', [])
        tests = entry.get('tests', [])
        note = entry.get('note', '')

        # Validate id
        if not entry_id:
            errors.append({'type': 'missing_id', 'index': i, 'message': 'Entry missing "id"'})
            continue

        if not isinstance(entry_id, str) or not re.match(r'^TR-\d{4}$', entry_id):
            errors.append({
                'type': 'invalid_id_format',
                'id': entry_id,
                'message': f'ID must match TR-NNNN: {entry_id}'
            })

        if entry_id in seen_ids:
            errors.append({
                'type': 'duplicate_id',
                'id': entry_id,
                'message': f'Duplicate ID: {entry_id}'
            })
        seen_ids.add(entry_id)

        # Validate section
        if not section or not isinstance(section, str):
            errors.append({
                'type': 'invalid_section',
                'id': entry_id,
                'message': 'Entry missing or invalid "section"'
            })
            continue

        # Validate section format (simple check - can be 1-12 or 1.1-1.8 etc)
        if not re.match(r'^\d+(?:\.\d+)?$', section):
            errors.append({
                'type': 'invalid_section_format',
                'id': entry_id,
                'section': section,
                'message': f'Section must be numeric like "7" or "7.3": {section}'
            })

        # Validate status
        if not status or status not in ('active', 'unimplemented', 'superseded'):
            errors.append({
                'type': 'invalid_status',
                'id': entry_id,
                'status': status,
                'message': f'Status must be "active", "unimplemented", or "superseded": {status}'
            })

        # Validate modules for active entries
        if status == 'active':
            if not modules or not isinstance(modules, list) or len(modules) == 0:
                errors.append({
                    'type': 'active_empty_modules',
                    'id': entry_id,
                    'section': section,
                    'message': f'Active entry must have at least one module'
                })

            if isinstance(modules, list):
                for module in modules:
                    if not isinstance(module, str):
                        errors.append({
                            'type': 'invalid_module_type',
                            'id': entry_id,
                            'message': f'Module path must be string'
                        })
                    elif not module.startswith('rules/'):
                        errors.append({
                            'type': 'invalid_module_path',
                            'id': entry_id,
                            'module': module,
                            'message': f'Module path must start with "rules/": {module}'
                        })

        # Track active sections
        if status == 'active':
            if section in seen_active_sections:
                errors.append({
                    'type': 'duplicate_active_section',
                    'id': entry_id,
                    'section': section,
                    'message': f'Duplicate active entry for section: {section}'
                })
            seen_active_sections.add(section)

    return data, errors


def resolve(section_id: str, index: Dict[str, Any]) -> Tuple[Optional[Dict[str, Any]], str]:
    """
    Resolve which entry covers a section (direct or inherited from parent).

    Returns (entry, resolution_type) where resolution_type is "direct" or "inherited".
    Returns (None, "not_found") if neither the section nor its parent is in the index.
    """
    entries = index.get('entries', [])

    # Look for direct entry
    for entry in entries:
        if entry.get('section') == section_id:
            return entry, 'direct'

    # Look for parent entry
    parent = parent_of(section_id)
    if parent:
        for entry in entries:
            if entry.get('section') == parent:
                return entry, 'inherited'

    return None, 'not_found'


if __name__ == '__main__':
    # Simple test/demo
    import sys

    if len(sys.argv) > 1:
        spec_path = sys.argv[1]
        with open(spec_path, 'r') as f:
            spec_text = f.read()

        sections = parse_sections(spec_text)
        print(f"Found {len(sections)} sections:")
        for s in sections[:5]:
            print(f"  {s['id']}: {s['title']}")
