import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import 'theme.dart';

/// Maps each [ItemCategory] to a Material **outlined** icon and renders it
/// inside a soft tinted "chip" — a rounded square in [HavenColors.primary]
/// at low opacity with the icon in full-strength primary. Every category
/// reads at a consistent stroke weight, which is what makes the items list
/// / item-detail hero / add-item grid feel cohesive instead of like a
/// dropped-in emoji set.
///
/// Not meant to be instantiated.
class CategoryIcon {
  CategoryIcon._();

  /// The Material icon for a category. Use this when you need the raw
  /// [IconData] (e.g. to draw it yourself at an arbitrary size or color);
  /// most callers want [widget] instead.
  static IconData iconData(ItemCategory category) => switch (category) {
        // --- Major appliances ---------------------------------------
        ItemCategory.refrigerator => Icons.kitchen_outlined,
        ItemCategory.freezer => Icons.kitchen_outlined,
        ItemCategory.dishwasher => Icons.countertops_outlined,
        ItemCategory.washer => Icons.local_laundry_service_outlined,
        ItemCategory.dryer => Icons.dry_cleaning_outlined,
        ItemCategory.oven_range => Icons.local_fire_department_outlined,
        ItemCategory.microwave => Icons.microwave_outlined,
        ItemCategory.garbage_disposal => Icons.delete_sweep_outlined,
        ItemCategory.range_hood => Icons.air_outlined,
        ItemCategory.trash_compactor => Icons.compress_outlined,
        ItemCategory.wine_cooler => Icons.wine_bar_outlined,
        ItemCategory.coffee_maker => Icons.coffee_maker_outlined,
        ItemCategory.grill => Icons.outdoor_grill_outlined,

        // --- HVAC / climate / water ---------------------------------
        ItemCategory.hvac => Icons.ac_unit_outlined,
        ItemCategory.furnace => Icons.local_fire_department_outlined,
        ItemCategory.ceiling_fan => Icons.mode_fan_off_outlined,
        ItemCategory.air_purifier => Icons.air_outlined,
        ItemCategory.dehumidifier => Icons.water_damage_outlined,
        ItemCategory.water_heater => Icons.water_drop_outlined,
        ItemCategory.water_softener => Icons.opacity_outlined,
        ItemCategory.sump_pump => Icons.waves_outlined,

        // --- Electronics --------------------------------------------
        ItemCategory.tv => Icons.tv_outlined,
        ItemCategory.home_theater => Icons.theaters_outlined,
        ItemCategory.computer => Icons.computer_outlined,
        ItemCategory.printer => Icons.print_outlined,
        ItemCategory.networking => Icons.router_outlined,
        ItemCategory.camera => Icons.photo_camera_outlined,
        ItemCategory.smart_home => Icons.home_outlined,

        // --- Building / structure -----------------------------------
        ItemCategory.roofing => Icons.roofing_outlined,
        ItemCategory.windows => Icons.window_outlined,
        ItemCategory.doors => Icons.door_front_door_outlined,
        ItemCategory.flooring => Icons.grid_on_outlined,
        ItemCategory.plumbing => Icons.plumbing_outlined,
        ItemCategory.electrical => Icons.electrical_services_outlined,
        ItemCategory.lighting => Icons.lightbulb_outline,

        // --- Safety / security --------------------------------------
        ItemCategory.smoke_detector => Icons.sensors_outlined,
        ItemCategory.security_system => Icons.shield_outlined,
        ItemCategory.garage_door_opener => Icons.garage_outlined,

        // --- Tools / outdoor / furniture ----------------------------
        ItemCategory.power_tools => Icons.handyman_outlined,
        ItemCategory.lawn_mower => Icons.grass_outlined,
        ItemCategory.pool_equipment => Icons.pool_outlined,
        ItemCategory.vacuum => Icons.cleaning_services_outlined,
        ItemCategory.furniture => Icons.chair_outlined,

        ItemCategory.other => Icons.category_outlined,
      };

  /// Renders the category icon inside the standard tinted chip.
  ///
  /// [size] is the icon glyph size; the chip is sized proportionally
  /// (~1.75×) with the corner radius scaled to the chip, so a `size: 24`
  /// glyph yields a ~42dp chip — matching the previous emoji footprint at
  /// the list/grid call sites. Pass `boxed: false` for the bare icon with
  /// no chip (e.g. inside a row that already has its own container).
  static Widget widget(
    ItemCategory category, {
    double size = 24,
    bool boxed = true,
    Color? color,
  }) {
    final tint = color ?? HavenColors.primary;
    final icon = Icon(iconData(category), size: size, color: tint);

    if (!boxed) {
      return Semantics(
        label: category.displayLabel,
        excludeSemantics: true,
        child: icon,
      );
    }

    final box = size * 1.75;
    return Semantics(
      label: category.displayLabel,
      excludeSemantics: true,
      child: Container(
        width: box,
        height: box,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(
            (box * 0.32).clamp(HavenRadius.micro, HavenRadius.card),
          ),
          border: Border.all(color: tint.withValues(alpha: 0.16)),
        ),
        child: icon,
      ),
    );
  }
}
