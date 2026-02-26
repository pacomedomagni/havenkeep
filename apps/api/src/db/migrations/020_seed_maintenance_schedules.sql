-- Migration 020: Seed maintenance schedules for remaining 37 item categories
-- The following 7 categories already have schedules from migration 002:
--   hvac, water_heater, refrigerator, dishwasher, washer, dryer, garbage_disposal
--
-- This migration adds 1-3 realistic maintenance tasks for each of the remaining 37 categories.

INSERT INTO maintenance_schedules (category, task_name, description, frequency_months, frequency_label, estimated_duration_minutes, difficulty, prevents_cost, priority) VALUES

  -- ============================================
  -- KITCHEN APPLIANCES
  -- ============================================

  -- Oven / Range
  ('oven_range', 'Deep Clean Oven Interior', 'Run self-clean cycle or manually clean oven interior to remove grease and baked-on residue', 3, 'Quarterly', 30, 'easy', 100.00, 7),
  ('oven_range', 'Inspect and Clean Burners', 'Remove burner grates and caps, clean ports and igniters to ensure even flame', 6, 'Semi-annually', 20, 'easy', 150.00, 6),
  ('oven_range', 'Check Door Seal and Hinges', 'Inspect oven door gasket for wear and hinges for proper closure to maintain heat efficiency', 12, 'Annually', 10, 'easy', 80.00, 5),

  -- Microwave
  ('microwave', 'Clean Interior and Turntable', 'Wipe down interior walls, ceiling, and turntable with mild cleaner to prevent odors and buildup', 1, 'Monthly', 10, 'easy', 50.00, 5),
  ('microwave', 'Inspect Door Seal and Latch', 'Check door seal for damage and ensure latch closes securely to prevent radiation leakage', 12, 'Annually', 5, 'easy', 200.00, 7),

  -- Range Hood
  ('range_hood', 'Clean or Replace Grease Filter', 'Remove grease filter and soak in hot soapy water or replace disposable filter', 3, 'Quarterly', 15, 'easy', 120.00, 7),
  ('range_hood', 'Clean Fan Blades and Housing', 'Degrease fan blades and interior housing to maintain proper airflow', 6, 'Semi-annually', 25, 'medium', 150.00, 6),
  ('range_hood', 'Check and Clean Ductwork', 'Inspect exhaust ductwork for grease buildup and blockages', 12, 'Annually', 45, 'hard', 250.00, 5),

  -- Coffee Maker
  ('coffee_maker', 'Descale and Clean', 'Run descaling solution through the machine to remove mineral deposits', 3, 'Quarterly', 30, 'easy', 80.00, 7),
  ('coffee_maker', 'Replace Water Filter', 'Replace built-in water filter cartridge if equipped', 2, 'Bi-monthly', 5, 'easy', 40.00, 5),

  -- Wine Cooler
  ('wine_cooler', 'Clean Condenser Coils', 'Vacuum dust and debris from condenser coils to maintain cooling efficiency', 6, 'Semi-annually', 15, 'easy', 150.00, 7),
  ('wine_cooler', 'Check Door Seal and Temperature', 'Inspect door gasket for proper seal and verify thermostat accuracy', 6, 'Semi-annually', 10, 'easy', 100.00, 6),

  -- Trash Compactor
  ('trash_compactor', 'Clean and Deodorize Interior', 'Wipe down interior walls and ram with disinfectant, replace deodorizer', 1, 'Monthly', 15, 'easy', 60.00, 6),
  ('trash_compactor', 'Inspect Ram and Drive Mechanism', 'Check compaction ram, drive chain or screw, and lubricate moving parts', 12, 'Annually', 20, 'medium', 200.00, 7),

  -- Freezer
  ('freezer', 'Defrost and Clean Interior', 'Defrost frost buildup and wipe down interior surfaces', 6, 'Semi-annually', 45, 'easy', 120.00, 7),
  ('freezer', 'Check Door Seal', 'Inspect door gasket for cracks or gaps that allow warm air in', 12, 'Annually', 5, 'easy', 100.00, 6),
  ('freezer', 'Clean Condenser Coils', 'Vacuum or brush condenser coils to maintain cooling efficiency', 12, 'Annually', 15, 'easy', 150.00, 7),

  -- ============================================
  -- HOME SYSTEMS
  -- ============================================

  -- Furnace
  ('furnace', 'Replace Air Filter', 'Replace furnace air filter to maintain heating efficiency and air quality', 3, 'Quarterly', 5, 'easy', 200.00, 9),
  ('furnace', 'Annual Professional Inspection', 'Professional furnace inspection including heat exchanger, burner, and safety controls', 12, 'Annually', 60, 'hard', 600.00, 10),
  ('furnace', 'Clean Blower Assembly', 'Clean blower fan blades and motor to ensure proper airflow', 12, 'Annually', 30, 'medium', 250.00, 7),

  -- Water Softener
  ('water_softener', 'Check and Refill Salt', 'Inspect salt level in brine tank and refill as needed', 1, 'Monthly', 10, 'easy', 50.00, 7),
  ('water_softener', 'Clean Brine Tank', 'Drain and scrub brine tank to remove salt bridges and mushing', 12, 'Annually', 45, 'medium', 150.00, 6),
  ('water_softener', 'Inspect and Clean Resin Bed', 'Run resin cleaner through the system to maintain softening capacity', 6, 'Semi-annually', 15, 'easy', 200.00, 7),

  -- Sump Pump
  ('sump_pump', 'Test Pump Operation', 'Pour water into the pit to verify pump activates and drains properly', 3, 'Quarterly', 10, 'easy', 500.00, 10),
  ('sump_pump', 'Clean Pit and Check Valve', 'Remove debris from sump pit and inspect check valve for proper operation', 6, 'Semi-annually', 20, 'medium', 300.00, 8),
  ('sump_pump', 'Test Battery Backup', 'Verify battery backup system is charged and functional', 6, 'Semi-annually', 10, 'easy', 400.00, 9),

  -- Plumbing
  ('plumbing', 'Inspect for Leaks', 'Check under sinks, around toilets, and near water heater for signs of leaks', 6, 'Semi-annually', 20, 'easy', 300.00, 8),
  ('plumbing', 'Flush Water Lines', 'Run all faucets and flush toilets in unused areas to prevent stagnation and buildup', 3, 'Quarterly', 10, 'easy', 100.00, 5),
  ('plumbing', 'Drain Water Heater Sediment', 'Flush a few gallons from the water heater drain valve to remove sediment', 12, 'Annually', 20, 'medium', 250.00, 7),

  -- Electrical
  ('electrical', 'Test GFCI Outlets', 'Press test and reset buttons on all GFCI outlets to verify proper operation', 6, 'Semi-annually', 10, 'easy', 150.00, 9),
  ('electrical', 'Inspect Electrical Panel', 'Check breaker panel for signs of corrosion, heat damage, or loose connections', 12, 'Annually', 15, 'medium', 500.00, 8),
  ('electrical', 'Test Surge Protectors', 'Verify whole-house and plug-in surge protectors are functioning', 12, 'Annually', 10, 'easy', 300.00, 7),

  -- ============================================
  -- EXTERIOR / STRUCTURAL
  -- ============================================

  -- Roofing
  ('roofing', 'Inspect Roof and Flashings', 'Visually inspect shingles, flashings, and vents for damage or wear', 6, 'Semi-annually', 30, 'medium', 500.00, 9),
  ('roofing', 'Clean Gutters and Downspouts', 'Remove leaves and debris from gutters, flush downspouts to ensure proper drainage', 6, 'Semi-annually', 45, 'medium', 300.00, 8),
  ('roofing', 'Check Attic for Leaks', 'Inspect attic underside for water stains, mold, or daylight penetration', 12, 'Annually', 20, 'easy', 400.00, 7),

  -- Windows
  ('windows', 'Inspect Weatherstripping and Caulk', 'Check window seals, weatherstripping, and caulk for gaps or deterioration', 12, 'Annually', 30, 'easy', 200.00, 7),
  ('windows', 'Clean Tracks and Lubricate Hardware', 'Vacuum window tracks, clean frames, and lubricate locks and hinges', 6, 'Semi-annually', 20, 'easy', 100.00, 5),

  -- Doors
  ('doors', 'Lubricate Hinges and Locks', 'Apply lubricant to all door hinges, deadbolts, and lock mechanisms', 12, 'Annually', 15, 'easy', 80.00, 5),
  ('doors', 'Inspect Weatherstripping', 'Check door weatherstripping and sweeps for gaps causing drafts or moisture intrusion', 12, 'Annually', 15, 'easy', 150.00, 6),
  ('doors', 'Check Alignment and Operation', 'Verify doors close and latch properly, adjust strike plates and hinges if needed', 12, 'Annually', 20, 'medium', 120.00, 5),

  -- Flooring
  ('flooring', 'Deep Clean and Condition', 'Deep clean floors appropriate to material type and apply conditioner or sealant as needed', 6, 'Semi-annually', 60, 'easy', 200.00, 6),
  ('flooring', 'Inspect for Damage', 'Check for loose tiles, cracked grout, warped boards, or carpet wear', 12, 'Annually', 20, 'easy', 300.00, 7),

  -- Garage Door Opener
  ('garage_door_opener', 'Lubricate Moving Parts', 'Apply garage door lubricant to rollers, hinges, tracks, and springs', 6, 'Semi-annually', 15, 'easy', 150.00, 7),
  ('garage_door_opener', 'Test Safety Reversal', 'Place object under door to verify auto-reverse safety feature works properly', 3, 'Quarterly', 5, 'easy', 200.00, 9),
  ('garage_door_opener', 'Inspect Springs and Cables', 'Visually check torsion springs and lift cables for fraying or wear', 12, 'Annually', 10, 'medium', 400.00, 8),

  -- ============================================
  -- ELECTRONICS & TECHNOLOGY
  -- ============================================

  -- TV
  ('tv', 'Clean Screen and Vents', 'Gently clean display with microfiber cloth and clear dust from ventilation openings', 3, 'Quarterly', 10, 'easy', 50.00, 4),
  ('tv', 'Check and Organize Cables', 'Inspect cable connections for corrosion, ensure secure fit, and manage cable clutter', 12, 'Annually', 15, 'easy', 60.00, 3),

  -- Computer
  ('computer', 'Clean Dust from Interior', 'Use compressed air to clean dust from fans, heatsinks, and components', 6, 'Semi-annually', 20, 'medium', 150.00, 7),
  ('computer', 'Update and Backup System', 'Apply OS and software updates, verify automatic backups are running', 3, 'Quarterly', 30, 'easy', 300.00, 8),

  -- Smart Home
  ('smart_home', 'Update Firmware', 'Check and install firmware updates for smart home hub and connected devices', 3, 'Quarterly', 20, 'easy', 100.00, 7),
  ('smart_home', 'Test Automations and Sensors', 'Verify all automations trigger correctly and sensor batteries are charged', 6, 'Semi-annually', 30, 'easy', 80.00, 6),
  ('smart_home', 'Review Security Settings', 'Audit device access permissions, change default passwords, review network security', 12, 'Annually', 30, 'medium', 200.00, 8),

  -- Home Theater
  ('home_theater', 'Clean Components and Vents', 'Dust receiver, speakers, and projector; clear ventilation openings', 3, 'Quarterly', 15, 'easy', 100.00, 5),
  ('home_theater', 'Calibrate Audio and Video', 'Run audio calibration and verify video settings for optimal performance', 12, 'Annually', 45, 'medium', 80.00, 4),
  ('home_theater', 'Inspect and Organize Wiring', 'Check all cable connections, replace worn cables, and manage cable routing', 12, 'Annually', 30, 'easy', 60.00, 3),

  -- Printer
  ('printer', 'Clean Print Heads', 'Run built-in print head cleaning cycle to prevent clogged nozzles', 1, 'Monthly', 5, 'easy', 100.00, 6),
  ('printer', 'Clean Paper Path and Rollers', 'Wipe feed rollers and clean paper path to prevent jams', 6, 'Semi-annually', 15, 'easy', 80.00, 5),

  -- Networking
  ('networking', 'Restart Router and Modem', 'Power cycle networking equipment to clear memory and refresh connections', 3, 'Quarterly', 5, 'easy', 50.00, 5),
  ('networking', 'Update Router Firmware', 'Check for and install router firmware updates for security and performance', 6, 'Semi-annually', 15, 'easy', 150.00, 8),
  ('networking', 'Audit Connected Devices', 'Review list of connected devices, remove unknown entries, and update Wi-Fi password', 12, 'Annually', 20, 'medium', 200.00, 7),

  -- Camera (security cameras / photography equipment)
  ('camera', 'Clean Lens and Housing', 'Wipe camera lens and clean housing or weatherproof enclosure', 3, 'Quarterly', 10, 'easy', 60.00, 6),
  ('camera', 'Check Storage and Recordings', 'Verify recording storage capacity, review footage retention settings, and clear old files', 6, 'Semi-annually', 15, 'easy', 100.00, 7),
  ('camera', 'Update Firmware', 'Install latest camera firmware updates for security patches and feature improvements', 6, 'Semi-annually', 10, 'easy', 80.00, 7),

  -- ============================================
  -- SAFETY & SECURITY
  -- ============================================

  -- Smoke Detector
  ('smoke_detector', 'Test and Replace Batteries', 'Press test button to verify alarm sounds and replace 9V or AA batteries', 6, 'Semi-annually', 10, 'easy', 500.00, 10),
  ('smoke_detector', 'Clean and Vacuum Sensor', 'Vacuum around smoke detector vents to remove dust that can cause false alarms or failures', 12, 'Annually', 5, 'easy', 300.00, 8),

  -- Security System
  ('security_system', 'Test All Sensors', 'Walk-test motion detectors, open doors and windows to verify all sensors report correctly', 3, 'Quarterly', 20, 'easy', 200.00, 9),
  ('security_system', 'Replace Sensor Batteries', 'Check and replace batteries in wireless door, window, and motion sensors', 12, 'Annually', 30, 'easy', 150.00, 8),
  ('security_system', 'Update System Firmware', 'Install security panel and camera firmware updates for vulnerability patches', 6, 'Semi-annually', 15, 'easy', 250.00, 8),

  -- ============================================
  -- OUTDOOR / LAWN & GARDEN
  -- ============================================

  -- Lawn Mower
  ('lawn_mower', 'Change Oil', 'Drain old oil and replace with fresh oil per manufacturer specifications', 12, 'Annually', 20, 'medium', 150.00, 7),
  ('lawn_mower', 'Sharpen or Replace Blade', 'Remove and sharpen mower blade or replace if excessively worn', 12, 'Annually', 30, 'medium', 80.00, 6),
  ('lawn_mower', 'Replace Air Filter and Spark Plug', 'Install new air filter and spark plug for reliable starting and clean operation', 12, 'Annually', 15, 'easy', 100.00, 7),

  -- Pool Equipment
  ('pool_equipment', 'Clean Pool Filter', 'Backwash or disassemble and clean pool filter cartridge or DE grids', 1, 'Monthly', 30, 'medium', 200.00, 8),
  ('pool_equipment', 'Inspect Pump and Motor', 'Check pump basket, seals, and motor for leaks, unusual noise, or vibration', 6, 'Semi-annually', 20, 'medium', 350.00, 8),
  ('pool_equipment', 'Test and Balance Water Chemistry', 'Test pH, chlorine, alkalinity, and calcium hardness; adjust chemicals as needed', 1, 'Weekly to Monthly', 15, 'easy', 250.00, 9),

  -- Grill
  ('grill', 'Deep Clean Grates and Burners', 'Remove and scrub grill grates, clean burner tubes and ports, empty grease trap', 3, 'Quarterly', 30, 'easy', 100.00, 6),
  ('grill', 'Inspect Gas Connections', 'Check gas hose and connections for cracks or leaks using soapy water test', 6, 'Semi-annually', 10, 'easy', 200.00, 9),
  ('grill', 'Season and Cover', 'Oil grates to prevent rust and ensure cover fits properly for weather protection', 6, 'Semi-annually', 15, 'easy', 80.00, 5),

  -- Power Tools
  ('power_tools', 'Clean and Inspect', 'Wipe down tools, clean vents, check cords and switches for damage', 6, 'Semi-annually', 20, 'easy', 100.00, 6),
  ('power_tools', 'Lubricate Moving Parts', 'Apply appropriate lubricant to chucks, bearings, and adjustment mechanisms', 12, 'Annually', 15, 'easy', 80.00, 5),
  ('power_tools', 'Replace Worn Blades and Bits', 'Inspect and replace dull or damaged saw blades, drill bits, and sanding discs', 12, 'Annually', 20, 'medium', 120.00, 6),

  -- ============================================
  -- CLIMATE & AIR QUALITY
  -- ============================================

  -- Air Purifier
  ('air_purifier', 'Replace HEPA Filter', 'Replace main HEPA filter according to manufacturer schedule', 12, 'Annually', 10, 'easy', 100.00, 8),
  ('air_purifier', 'Clean Pre-Filter', 'Remove and wash or vacuum the pre-filter to extend HEPA filter life', 1, 'Monthly', 5, 'easy', 50.00, 6),

  -- Dehumidifier
  ('dehumidifier', 'Clean Water Collection Bucket', 'Empty and wash reservoir bucket with mild cleaner to prevent mold and bacteria', 1, 'Monthly', 10, 'easy', 60.00, 7),
  ('dehumidifier', 'Clean Filter and Coils', 'Remove and clean air filter, wipe down evaporator coils to maintain efficiency', 3, 'Quarterly', 15, 'easy', 120.00, 7),
  ('dehumidifier', 'Inspect Drainage Hose', 'Check continuous drain hose for kinks, clogs, or leaks', 6, 'Semi-annually', 5, 'easy', 80.00, 5),

  -- Ceiling Fan
  ('ceiling_fan', 'Clean Blades and Motor Housing', 'Wipe down fan blades and dust motor housing to prevent wobble and maintain airflow', 3, 'Quarterly', 10, 'easy', 50.00, 5),
  ('ceiling_fan', 'Tighten Screws and Check Balance', 'Tighten blade screws, light fixture, and mounting hardware; balance blades if wobbling', 12, 'Annually', 15, 'easy', 80.00, 6),

  -- ============================================
  -- CLEANING EQUIPMENT
  -- ============================================

  -- Vacuum
  ('vacuum', 'Clean or Replace Filters', 'Wash reusable filters or replace disposable HEPA filters per manufacturer guidance', 3, 'Quarterly', 10, 'easy', 80.00, 7),
  ('vacuum', 'Clear Brush Roll and Check Belt', 'Remove tangled hair and debris from brush roll, inspect drive belt for stretching or cracks', 3, 'Quarterly', 10, 'easy', 60.00, 6),
  ('vacuum', 'Check Hose and Attachments', 'Inspect hose for clogs or cracks, verify attachments connect securely', 6, 'Semi-annually', 10, 'easy', 50.00, 5),

  -- ============================================
  -- LIGHTING
  -- ============================================

  -- Lighting
  ('lighting', 'Clean Fixtures and Diffusers', 'Remove and wash light fixture covers, globes, and diffusers to maximize light output', 6, 'Semi-annually', 20, 'easy', 40.00, 4),
  ('lighting', 'Check for Flickering and Replace Bulbs', 'Identify failing or flickering bulbs and replace with correct type and wattage', 6, 'Semi-annually', 15, 'easy', 60.00, 5),

  -- ============================================
  -- FURNITURE
  -- ============================================

  -- Furniture
  ('furniture', 'Condition Wood Surfaces', 'Apply wood conditioner or polish to wood furniture to prevent drying and cracking', 6, 'Semi-annually', 30, 'easy', 150.00, 5),
  ('furniture', 'Tighten Hardware and Check Joints', 'Tighten bolts, screws, and fasteners on tables, chairs, and bed frames', 12, 'Annually', 20, 'easy', 100.00, 6),
  ('furniture', 'Deep Clean Upholstery', 'Vacuum and spot-clean or steam-clean upholstered furniture and cushions', 6, 'Semi-annually', 45, 'easy', 120.00, 5),

  -- ============================================
  -- OTHER
  -- ============================================

  -- Other (general catch-all)
  ('other', 'General Inspection', 'Perform a visual inspection for wear, damage, or maintenance needs', 6, 'Semi-annually', 15, 'easy', 100.00, 5),
  ('other', 'Clean and Maintain', 'Clean the item according to manufacturer instructions and check for proper operation', 6, 'Semi-annually', 20, 'easy', 80.00, 5)

ON CONFLICT DO NOTHING;

DO $$
BEGIN
  RAISE NOTICE 'Migration 020: Seeded maintenance schedules for 37 additional item categories (approximately 90 new tasks)';
END $$;
