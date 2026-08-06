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
        <Box bold>No target designated.</Box>
        <LabeledList>
          <ShieldListItem label="Own Shields" shields={data.own_shields} />
        </LabeledList>
      </Section>
    );
  } else {
    return (
      <Section>
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
