#!/usr/bin/env python3
"""
Add DequeueWidgets widget extension target to the Dequeue Xcode project.
Uses the pbxproj library to safely modify the project.pbxproj file.
"""

import sys
import os

# Add the project root to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pbxproj import XcodeProject
from pbxproj.pbxsections import PBXBuildFile

PROJECT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    'Dequeue', 'Dequeue.xcodeproj', 'project.pbxproj'
)

WIDGET_TARGET_NAME = 'DequeueWidgets'
WIDGET_BUNDLE_ID = 'com.ardonos.Dequeue.widgets'

# Widget source files (relative to Dequeue/)
WIDGET_SOURCES = [
    'DequeueWidgets/DequeueWidgetBundle.swift',
    'DequeueWidgets/ActiveStackWidget.swift',
    'DequeueWidgets/UpNextWidget.swift',
    'DequeueWidgets/QuickStatsWidget.swift',
]

# Shared files (added to both main app and widget targets)
SHARED_SOURCES = [
    'Shared/WidgetModels.swift',
]

def main():
    print(f"Loading project: {PROJECT_PATH}")
    project = XcodeProject.load(PROJECT_PATH)
    
    # Check if target already exists
    for target in project.objects.get_targets():
        if target.name == WIDGET_TARGET_NAME:
            print(f"Target '{WIDGET_TARGET_NAME}' already exists. Skipping.")
            return
    
    # Add widget source files to the project
    print("Adding widget source files...")
    
    # Add shared files to main app target first
    for source in SHARED_SOURCES:
        full_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            'Dequeue', source
        )
        if os.path.exists(full_path):
            # Add to main app target
            result = project.add_file(
                full_path,
                parent=None,
                target_name='Dequeue'
            )
            if result:
                print(f"  Added {source} to Dequeue target")
            else:
                print(f"  {source} may already exist in project")
    
    # Save the project
    print("Saving project...")
    project.save()
    print("Done! Shared files added to main Dequeue target.")
    print()
    print("NOTE: The widget extension target (DequeueWidgets) needs to be added")
    print("through Xcode: File > New > Target > Widget Extension.")
    print("Then add the widget source files to that target.")
    print()
    print("Widget files to add:")
    for source in WIDGET_SOURCES:
        print(f"  - Dequeue/{source}")
    print(f"  - Dequeue/Shared/WidgetModels.swift (add to BOTH targets)")


if __name__ == '__main__':
    main()
