import {
  Box,
  Button,
  LabeledList,
  NoticeBox,
  ProgressBar,
  Section,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend } from '../backend';
import { Window } from '../layouts';

type PodPart = {
  slot: string;
  name: string | null;
  active: BooleanLike;
  disrupted: BooleanLike;
  shield_active_remaining?: number | null;
  shield_recharge_remaining?: number | null;
};

type PrimedSector = {
  name: string;
  distance: number;
};

type PodCockpitData = {
  on: BooleanLike;
  locked: BooleanLike;
  cell_charge: number | null;
  engine_fuel: number | null;
  parts: PodPart[];
  nav_available: BooleanLike;
  current_sector?: string;
  viewing_sector?: BooleanLike;
  primed_sector?: PrimedSector | null;
  jump_cooldown?: number;
  fuel_percent?: number | null;
  sensors_active: BooleanLike;
};

const slotLabel = (slot: string) =>
  slot
    .split('_')
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');

export const PodCockpit = (props) => {
  const { act, data } = useBackend<PodCockpitData>();
  const parts = data.parts || [];
  const engine = parts.find((part) => part.slot === 'engine');
  const weapon = parts.find((part) => part.slot === 'main_weapon');
  const lock = parts.find((part) => part.slot === 'lock');
  const otherParts = parts.filter(
    (part) =>
      part.slot !== 'engine' &&
      part.slot !== 'main_weapon' &&
      // The Hatch row below already controls the pod's real locked state
      // regardless of whether a lock part is installed -- a generic
      // toggle here would just flip a cosmetic flag with no real effect.
      part.slot !== 'lock',
  );

  return (
    <Window width={500} height={600}>
      <Window.Content scrollable>
        <Section title="Systems">
          <LabeledList>
            <LabeledList.Item label="Engine">
              <Button
                icon="power-off"
                selected={!!data.on}
                onClick={() => act('toggle_engine')}
              >
                {data.on ? 'Running' : 'Stopped'}
              </Button>
              {engine?.name && (
                <Button
                  icon="eject"
                  ml={1}
                  onClick={() => act('eject_part', { slot: 'engine' })}
                >
                  Eject Engine
                </Button>
              )}
            </LabeledList.Item>
            {data.cell_charge !== null && (
              <LabeledList.Item label="Cell Charge">
                <ProgressBar value={data.cell_charge} minValue={0} maxValue={100}>
                  {Math.round(data.cell_charge)}%
                </ProgressBar>
              </LabeledList.Item>
            )}
            {data.engine_fuel !== null && (
              <LabeledList.Item label="Engine Fuel">
                {data.engine_fuel}u phoron
                <Button
                  icon="eject"
                  ml={1}
                  onClick={() => act('eject_fuel')}
                >
                  Eject Tank
                </Button>
              </LabeledList.Item>
            )}
            <LabeledList.Item label="Hatch">
              <Button
                icon={data.locked ? 'lock' : 'lock-open'}
                selected={!!data.locked}
                onClick={() => act('toggle_lock')}
              >
                {data.locked ? 'Locked' : 'Unlocked'}
              </Button>
              {lock?.name && (
                <Button
                  icon="eject"
                  ml={1}
                  onClick={() => act('eject_part', { slot: 'lock' })}
                >
                  Eject Lock
                </Button>
              )}
            </LabeledList.Item>
            {otherParts.map((part) => (
              <LabeledList.Item key={part.slot} label={slotLabel(part.slot)}>
                {part.name ? (
                  <>
                    <Button
                      icon="power-off"
                      selected={!!part.active}
                      disabled={!!part.disrupted}
                      onClick={() => act('toggle_part', { slot: part.slot })}
                    >
                      {part.name} -- {part.active ? 'On' : 'Off'}
                    </Button>
                    <Button
                      icon="eject"
                      ml={1}
                      onClick={() => act('eject_part', { slot: part.slot })}
                    >
                      Eject
                    </Button>
                    {part.name === 'cargo hold' && (
                      <Button
                        icon="box-open"
                        ml={1}
                        onClick={() => act('open_cargo')}
                      >
                        Open Cargo
                      </Button>
                    )}
                    {part.name === 'light shielding system' && (
                      <>
                        {!!part.shield_active_remaining && (
                          <Box color="good" inline ml={1}>
                            Expires in {Math.ceil(part.shield_active_remaining / 10)}s
                          </Box>
                        )}
                        {!!part.shield_recharge_remaining && (
                          <Box color="average" inline ml={1}>
                            Recharging, {Math.ceil(part.shield_recharge_remaining / 10)}s left
                          </Box>
                        )}
                      </>
                    )}
                  </>
                ) : (
                  'Empty'
                )}
              </LabeledList.Item>
            ))}
          </LabeledList>
        </Section>

        <Section title="Weapon">
          {weapon?.name ? (
            <>
              <Button
                icon="power-off"
                selected={!!weapon.active}
                disabled={!!weapon.disrupted}
                onClick={() => act('toggle_part', { slot: 'main_weapon' })}
              >
                {weapon.active ? 'Online' : 'Offline'}
              </Button>
              <Button
                icon="crosshairs"
                color="bad"
                ml={1}
                disabled={!weapon.active}
                onClick={() => act('fire_weapon')}
              >
                Fire {weapon.name}
              </Button>
              <Button
                icon="eject"
                ml={1}
                onClick={() => act('eject_part', { slot: 'main_weapon' })}
              >
                Eject
              </Button>
            </>
          ) : (
            <NoticeBox>No weapon installed.</NoticeBox>
          )}
        </Section>

        <Section title="Navigation">
          {data.nav_available ? (
            <LabeledList>
              <LabeledList.Item label="Current Sector">
                {data.current_sector || 'Unknown'}
              </LabeledList.Item>
              {data.fuel_percent !== null && data.fuel_percent !== undefined && (
                <LabeledList.Item label="Warp Fuel">
                  <ProgressBar
                    value={data.fuel_percent}
                    minValue={0}
                    maxValue={100}
                  >
                    {Math.round(data.fuel_percent)}%
                  </ProgressBar>
                </LabeledList.Item>
              )}
              {!!data.jump_cooldown && (
                <LabeledList.Item label="Recharging">
                  {Math.ceil(data.jump_cooldown / 10)}s
                </LabeledList.Item>
              )}
              <LabeledList.Item label="Sector View">
                <Button
                  icon="eye"
                  selected={!!data.viewing_sector}
                  onClick={() => act('toggle_sector_view')}
                >
                  {data.viewing_sector ? 'Viewing' : 'Closed'}
                </Button>
                {!data.sensors_active && (
                  <Box color="average" inline ml={1}>
                    No sensors -- only charted sectors are visible.
                  </Box>
                )}
              </LabeledList.Item>
              <LabeledList.Item label="Jump Target">
                {data.primed_sector ? (
                  <>
                    {data.primed_sector.name} ({data.primed_sector.distance}{' '}
                    tiles)
                    <Button
                      icon="location-arrow"
                      ml={1}
                      disabled={!!data.jump_cooldown}
                      onClick={() => act('jump')}
                    >
                      Confirm Jump
                    </Button>
                  </>
                ) : (
                  'None primed -- open Sector View and click a sector.'
                )}
              </LabeledList.Item>
            </LabeledList>
          ) : (
            <NoticeBox>
              NO COMMS ARRAY -- cannot access navigation network.
            </NoticeBox>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
