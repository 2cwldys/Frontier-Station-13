import {
  Box,
  Button,
  Dropdown,
  LabeledList,
  Section,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { capitalizeAll } from 'tgui-core/string';
import { useBackend } from '../backend';
import { Window } from '../layouts';
import { MinimapView } from './common/MinimapView';

type ShipGun = {
  name: string;
  caliber: string;
  ammunition: string;
  ammunition_type: string;
};

type ShieldData = {
  shield_strength: number;
  max_shield_strength: number;
};

type ShieldControlData = {
  exists: BooleanLike;
  active: BooleanLike;
  anchored: BooleanLike;
  has_fuel: BooleanLike;
  at_away_site: BooleanLike;
  recovery_seconds_left: number;
};

type CloakControlData = {
  exists: BooleanLike;
  active: BooleanLike;
  anchored: BooleanLike;
  has_fuel: BooleanLike;
  at_away_site: BooleanLike;
  lockout_seconds_left: number;
};

type TractorControlData = {
  exists: BooleanLike;
  active: BooleanLike;
  anchored: BooleanLike;
  has_fuel: BooleanLike;
  at_away_site: BooleanLike;
  locked_target_name: string | null;
};

export type GunneryData = {
  guns: ShipGun[];
  cannon: ShipGun;
  gun_list: string[];
  entry_points: string[];
  z_levels: string[];
  selected_z: number;
  targeting: Targeting;
  selected_entrypoint: string;
  mobile_platform: BooleanLike;
  platform_directions: string[];
  platform_direction: string;
  entry_point_map_image: any; // base64 icon
  entry_point_x: number;
  entry_point_y: number;
  own_shields: ShieldData | null;
  target_shields: ShieldData | null;
  own_shield_control: ShieldControlData;
  own_cloak_control: CloakControlData;
  own_tractor_control: TractorControlData;
  held_by_tractor: BooleanLike;
  break_free_seconds_left: number;
};

const ShieldListItem = (props: { label: string; shields: ShieldData | null }) => {
  const { label, shields } = props;
  if (!shields) {
    return (
      <LabeledList.Item label={label}>No shields detected.</LabeledList.Item>
    );
  }
  const percent = shields.max_shield_strength
    ? Math.round(
        (shields.shield_strength / shields.max_shield_strength) * 100,
      )
    : 0;
  return (
    <LabeledList.Item label={label}>
      {shields.shield_strength} / {shields.max_shield_strength} ({percent}%)
    </LabeledList.Item>
  );
};

const ShieldControlItem = (props: { control: ShieldControlData }) => {
  const { act } = useBackend<GunneryData>();
  const { control } = props;
  if (!control?.exists) {
    return null;
  }
  const recovering = !control.active && control.recovery_seconds_left > 0;
  const disabled =
    recovering ||
    !control.anchored ||
    (!control.active && !control.has_fuel) ||
    (!control.active && !!control.at_away_site);
  let reason = '';
  if (recovering) {
    reason = `Recalibrating after a shield collapse -- ready in ${control.recovery_seconds_left}s.`;
  } else if (!control.anchored) {
    reason = 'Shield generator is not anchored.';
  } else if (!control.active && !control.has_fuel) {
    reason = 'Shield generator has no fuel loaded.';
  } else if (!control.active && control.at_away_site) {
    reason = "Shields can't be raised at an away site.";
  }
  return (
    <LabeledList.Item label="Shield Control">
      <Button
        icon={control.active ? 'shield-alt' : 'shield'}
        content={control.active ? 'Deactivate' : 'Activate'}
        color={control.active ? 'good' : undefined}
        disabled={disabled}
        tooltip={reason || undefined}
        onClick={() => act('toggle_shields')}
      />
    </LabeledList.Item>
  );
};

const CloakControlItem = (props: { control: CloakControlData }) => {
  const { act } = useBackend<GunneryData>();
  const { control } = props;
  if (!control?.exists) {
    return null;
  }
  const locked = !control.active && control.lockout_seconds_left > 0;
  const disabled =
    locked ||
    !control.anchored ||
    (!control.active && !control.has_fuel) ||
    (!control.active && !!control.at_away_site);
  let reason = '';
  if (locked) {
    reason = `Recalibrating after firing -- ready in ${control.lockout_seconds_left}s.`;
  } else if (!control.anchored) {
    reason = 'Cloaking device is not anchored.';
  } else if (!control.active && !control.has_fuel) {
    reason = 'Cloaking device has no fuel loaded.';
  } else if (!control.active && control.at_away_site) {
    reason = "Can't cloak the ship at an away site.";
  }
  return (
    <LabeledList.Item label="Cloak Control">
      <Button
        icon={control.active ? 'eye-slash' : 'eye'}
        content={control.active ? 'Deactivate' : 'Activate'}
        color={control.active ? 'good' : undefined}
        disabled={disabled}
        tooltip={reason || undefined}
        onClick={() => act('toggle_cloak')}
      />
    </LabeledList.Item>
  );
};

const TractorControlItem = (props: { control: TractorControlData }) => {
  const { act } = useBackend<GunneryData>();
  const { control } = props;
  if (!control?.exists) {
    return null;
  }
  const disabled =
    !control.active &&
    (!control.anchored || !control.has_fuel || !!control.at_away_site);
  let reason = '';
  if (!control.anchored) {
    reason = 'Tractor beam projector is not anchored.';
  } else if (!control.has_fuel) {
    reason = 'Tractor beam projector has no fuel loaded.';
  } else if (control.at_away_site) {
    reason = "Can't lock onto anything at an away site.";
  } else if (!control.active) {
    reason = 'Requires a locked ship target within 1 tile.';
  }
  return (
    <LabeledList.Item label="Tractor Beam">
      <Button
        icon={control.active ? 'anchor' : 'crosshairs'}
        content={
          control.active
            ? `Release${control.locked_target_name ? ` (${control.locked_target_name})` : ''}`
            : 'Lock On'
        }
        color={control.active ? 'good' : undefined}
        disabled={disabled}
        tooltip={reason || undefined}
        onClick={() => act('toggle_tractor')}
      />
    </LabeledList.Item>
  );
};

const HeldByTractorSection = (props) => {
  const { act, data } = useBackend<GunneryData>();
  if (!data.held_by_tractor) {
    return null;
  }
  const onCooldown = data.break_free_seconds_left > 0;
  return (
    <Section title="Held by Tractor Beam">
      <Box color="bad" mb={1}>
        An enemy tractor beam has this ship pinned -- engines and shields are
        locked out.
      </Box>
      <Button
        icon="bolt"
        content={
          onCooldown
            ? `Overload Engines (${data.break_free_seconds_left}s)`
            : 'Attempt to Break Free'
        }
        color="bad"
        disabled={onCooldown}
        tooltip={
          onCooldown
            ? 'Recharging -- a failed attempt risks hull damage.'
            : 'A failed attempt risks hull damage from the strain.'
        }
        onClick={() => act('attempt_break_free')}
      />
    </Section>
  );
};

type Targeting = {
  name: string;
  shiptype: string;
  distance: number;
};

export const GunneryWindow = (props) => {
  const { act, data } = useBackend<GunneryData>();
  const { entry_points, z_levels, guns, platform_directions } = data;
  let gun_names: string[];
  gun_names = [];
  gun_names = guns.map((gun) => {
    return capitalizeAll(gun.name);
  });
  let target_name;
  if (data.targeting) {
    target_name = capitalizeAll(data.targeting.name);
  }
  let cannon_name;
  let cannon_caliber;
  if (data.cannon) {
    cannon_name = capitalizeAll(data.cannon.name);
    cannon_caliber = capitalizeAll(data.cannon.caliber);
  }
  if (!data.targeting) {
    return (
      <Section title="Targeting Information">
        <HeldByTractorSection />
        <Box bold>No target designated.</Box>
        <LabeledList>
          <ShieldListItem label="Own Shields" shields={data.own_shields} />
          <ShieldControlItem control={data.own_shield_control} />
          <CloakControlItem control={data.own_cloak_control} />
          <TractorControlItem control={data.own_tractor_control} />
        </LabeledList>
      </Section>
    );
  } else {
    return (
      <Section>
        <HeldByTractorSection />
        <Section title="Lock-On Information">
          <LabeledList>
            <LabeledList.Item label="Target">{target_name}</LabeledList.Item>
            <LabeledList.Item label="Type">
              {data.targeting.shiptype}
            </LabeledList.Item>
            <LabeledList.Item label="Distance">
              {data.targeting.distance} click(s)
            </LabeledList.Item>
            <ShieldListItem label="Own Shields" shields={data.own_shields} />
            <ShieldControlItem control={data.own_shield_control} />
            <CloakControlItem control={data.own_cloak_control} />
            <TractorControlItem control={data.own_tractor_control} />
            <ShieldListItem
              label="Target Shields"
              shields={data.target_shields}
            />
          </LabeledList>
        </Section>
        <Section title="Targeting Calibration">
          <Dropdown
            options={entry_points}
            displayText={data.selected_entrypoint}
            width="100%"
            selected={data.selected_entrypoint}
            onSelected={(value) =>
              act('select_entrypoint', { entrypoint: value })
            }
          />
          {data.z_levels ? (
            <Section>
              <Box bold>Deck Filter</Box>
              <Dropdown
                options={z_levels}
                displayText={data.selected_z}
                width="100%"
                selected={data.selected_z.toString()}
                onSelected={(value) => act('select_z', { z: value })}
              />
            </Section>
          ) : (
            ''
          )}
          {data.mobile_platform ? (
            <Section>
              <Dropdown
                options={platform_directions}
                displayText={data.platform_direction}
                width="100%"
                selected={data.platform_direction}
                onSelected={(value) =>
                  act('platform_direction', { dir: value })
                }
              />
            </Section>
          ) : (
            ''
          )}
        </Section>
        <Section title="Scan">
          {MinimapView({
            map_image: data.entry_point_map_image,
            x: data.entry_point_x,
            y: data.entry_point_y,
          })}
        </Section>
        <Section title="Weaponry Control">
          <Dropdown
            options={gun_names}
            width="100%"
            displayText={cannon_name ? cannon_name : ''}
            selected={cannon_name ? cannon_name : ''}
            onSelected={(value) => act('select_gun', { gun: value })}
          />
          {data.cannon && (
            <Section>
              <LabeledList>
                <LabeledList.Item label="Type">{cannon_name}</LabeledList.Item>
                <LabeledList.Item label="Caliber">
                  {cannon_caliber}
                </LabeledList.Item>
                <LabeledList.Item label="Loaded">
                  {data.cannon.ammunition}
                </LabeledList.Item>
                <LabeledList.Item label="Ammunition Type">
                  {data.cannon.ammunition_type}
                </LabeledList.Item>
              </LabeledList>
              <Button
                color="red"
                icon="exclamation-triangle"
                content="FIRE"
                onClick={() => act('fire')}
              />
            </Section>
          )}
        </Section>
      </Section>
    );
  }
};

export const Gunnery = (props) => {
  const { act, data } = useBackend<GunneryData>();
  return (
    <Window theme="zavodskoi">
      <Window.Content scrollable>
        <Section title="Ajax Targeting Console">
          <Button
            icon="calendar"
            color="red"
            content="View Targeting Grid"
            onClick={() => act('viewing')}
          />
          <GunneryWindow />
        </Section>
      </Window.Content>
    </Window>
  );
};
