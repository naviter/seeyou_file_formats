import 'activation_rules.dart';
import 'altitude_rules.dart';
import 'attribute_rules.dart';
import 'geometry_rules.dart';
import 'header_rules.dart';
import 'rule.dart';

/// A named group of rules. Used for documentation.
class RuleGroup {
  const RuleGroup(this.name, this.title, this.rules);

  /// A short name, for example `header`.
  final String name;

  /// A title for documentation, for example `Header`.
  final String title;

  /// The rules of this group.
  final List<Rule> rules;
}

/// All rule groups, in documentation order.
final List<RuleGroup> ruleGroups = [
  RuleGroup('header', 'Header and file', headerRules),
  RuleGroup('attributes', 'Airspace attributes (AC, AY, AN, AF, AG, AX)',
      attributeRules),
  RuleGroup('altitude', 'Altitude limits (AH, AL)', altitudeRules),
  RuleGroup('activation', 'Activation times (AA)', activationRules),
  RuleGroup('geometry', 'Geometry (DP, DA, DB, DC, DY, V)', geometryRules),
];

/// All rules of all groups.
final List<Rule> allRules = [
  for (final g in ruleGroups) ...g.rules,
];

final Map<String, Rule> _byId = {for (final r in allRules) r.id: r};

/// Returns the rule with this ID, or null.
Rule? findRule(String id) => _byId[id];
