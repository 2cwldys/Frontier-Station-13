import {
  Box,
  Button,
  Dropdown,
  NoticeBox,
  NumberInput,
  ProgressBar,
  Section,
  Table,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useState } from 'react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type Commodity = {
  key: string;
  name: string;
};

type CommodityPrice = {
  key: string;
  current_price: number;
  previous_price: number;
  price_high: number;
  price_low: number;
};

type BeaconEntry = {
  beacon_id: number;
  notes: string;
  x: number;
  y: number;
  in_range: BooleanLike;
  prices?: CommodityPrice[];
};

type TelepadChoice = {
  ref: string;
  area_name: string;
};

type SupplyBeaconTerminalData = {
  faction_uid: string | null;
  faction_name: string | null;
  faction_balance: number | null;
  is_personal: BooleanLike;
  personal_owner_name: string | null;
  personal_balance: number | null;
  is_crew: BooleanLike;
  crew_ship_name: string | null;
  crew_balance: number | null;
  commodities: Commodity[];
  beacons: BeaconEntry[];
  selected_beacon_id: number | null;
  selected_in_range: BooleanLike;
  cooldown_remaining: number;
  telepad_choices: TelepadChoice[];
  selected_telepad_ref: string | null;
  status_message: string;
};

const formatCooldown = (seconds: number) => {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return mins > 0 ? `${mins}m ${secs}s` : `${secs}s`;
};

export const SupplyBeaconTerminal = (props) => {
  const { act, data } = useBackend<SupplyBeaconTerminalData>();
  const {
    faction_uid,
    faction_name,
    faction_balance,
    is_personal,
    personal_owner_name,
    personal_balance,
    is_crew,
    crew_ship_name,
    crew_balance,
    commodities = [],
    beacons = [],
    selected_beacon_id,
    selected_in_range,
    cooldown_remaining,
    telepad_choices = [],
    selected_telepad_ref,
    status_message,
  } = data;

  if (!faction_uid && !is_personal && !is_crew) {
    return (
      <NtosWindow width={520} height={260}>
        <NtosWindow.Content>
          <NoticeBox>
            This console isn&apos;t linked to a faction, and isn&apos;t
            personally or crew tagged either. Tag it with a faction ID swipe
            or a faction tagger before it can trade with any Supply Beacon.
          </NoticeBox>
        </NtosWindow.Content>
      </NtosWindow>
    );
  }

  const commodityName = (key: string) =>
    commodities.find((c) => c.key === key)?.name ?? key;

  const selectedBeacon = beacons.find(
    (b) => b.beacon_id === selected_beacon_id,
  );

  return (
    <NtosWindow resizable width={720} height={640}>
      <NtosWindow.Content scrollable>
        {telepad_choices.length > 1 && (
          <Dropdown
            mb={1}
            width="100%"
            selected={
              telepad_choices.find((t) => t.ref === selected_telepad_ref)
                ?.area_name || 'Select a delivery telepad'
            }
            options={telepad_choices.map((t) => t.area_name)}
            onSelected={(area_name) => {
              const choice = telepad_choices.find(
                (t) => t.area_name === area_name,
              );
              if (choice) {
                act('select_telepad', { select_telepad: choice.ref });
              }
            }}
          />
        )}

        <Section title="Supply Beacon Terminal">
          {is_personal ? (
            <Box mb={1}>
              <Box bold>{personal_owner_name} — Personal Trading</Box>
              Personal Balance:{' '}
              <b>
                {personal_balance != null
                  ? `${personal_balance} credits`
                  : 'N/A'}
              </b>
            </Box>
          ) : is_crew ? (
            <Box mb={1}>
              <Box bold>{crew_ship_name ?? 'Ship'} — Crew Trading</Box>
              {crew_ship_name ?? 'Ship'} Balance:{' '}
              <b>{crew_balance != null ? `${crew_balance} credits` : 'N/A'}</b>
              <Box color="label">
                Purchases and sales bill/credit the ship owner&apos;s
                account, not yours.
              </Box>
            </Box>
          ) : (
            <Box mb={1}>
              <Box bold>{faction_name ?? faction_uid} — Faction Trading</Box>
              Faction Balance:{' '}
              <b>
                {faction_balance != null ? `${faction_balance} credits` : 'N/A'}
              </b>
            </Box>
          )}

          {status_message && (
            <Box
              bold
              mb={1}
              color={
                status_message.startsWith('Purchased') ||
                status_message.startsWith('Sold')
                  ? 'good'
                  : 'label'
              }
            >
              {status_message}
            </Box>
          )}

          <Box color="label" mb={1}>
            Fly your ship adjacent to (or onto) a beacon&apos;s overmap tile
            to see its prices and trade with it. Buying or selling locks that
            beacon out for your ship/faction/crew for 30 minutes.
          </Box>
        </Section>

        <Section title="Known Beacons">
          <Table>
            <Table.Row header>
              <Table.Cell>Beacon</Table.Cell>
              <Table.Cell>Position</Table.Cell>
              <Table.Cell>Range</Table.Cell>
              <Table.Cell />
            </Table.Row>
            {beacons.length ? (
              beacons.map((b) => (
                <Table.Row key={b.beacon_id}>
                  <Table.Cell bold>
                    {b.notes || `Supply Beacon #${b.beacon_id}`}
                  </Table.Cell>
                  <Table.Cell>
                    ({b.x}, {b.y})
                  </Table.Cell>
                  <Table.Cell color={b.in_range ? 'good' : 'label'}>
                    {b.in_range ? 'In range' : 'Out of range'}
                  </Table.Cell>
                  <Table.Cell>
                    <Button
                      selected={b.beacon_id === selected_beacon_id}
                      onClick={() =>
                        act('select_beacon', { beacon_id: b.beacon_id })
                      }
                    >
                      View
                    </Button>
                  </Table.Cell>
                </Table.Row>
              ))
            ) : (
              <Table.Row>
                <Table.Cell colSpan={4}>
                  No Supply Beacons have been placed yet.
                </Table.Cell>
              </Table.Row>
            )}
          </Table>
        </Section>

        {selectedBeacon && (
          <Section
            title={
              selectedBeacon.notes || `Supply Beacon #${selectedBeacon.beacon_id}`
            }
          >
            {!selected_in_range && (
              <NoticeBox color="orange">
                Out of range -- fly adjacent to this beacon&apos;s overmap
                tile to see its prices and trade.
              </NoticeBox>
            )}
            {selected_in_range && cooldown_remaining > 0 && (
              <NoticeBox color="orange">
                This beacon is on cooldown -- {formatCooldown(cooldown_remaining)}{' '}
                remaining before you can trade with it again.
              </NoticeBox>
            )}
            {selected_in_range && selectedBeacon.prices && (
              <Table>
                <Table.Row header>
                  <Table.Cell>Commodity</Table.Cell>
                  <Table.Cell>Price</Table.Cell>
                  <Table.Cell width="20%">Range (Low / High)</Table.Cell>
                  <Table.Cell>Trade</Table.Cell>
                </Table.Row>
                {selectedBeacon.prices.map((p) => (
                  <CommodityRow
                    key={p.key}
                    beaconId={selectedBeacon.beacon_id}
                    name={commodityName(p.key)}
                    price={p}
                    disabled={cooldown_remaining > 0}
                  />
                ))}
              </Table>
            )}
          </Section>
        )}
      </NtosWindow.Content>
    </NtosWindow>
  );
};

const CommodityRow = (props: {
  beaconId: number;
  name: string;
  price: CommodityPrice;
  disabled: boolean;
}) => {
  const { act } = useBackend<SupplyBeaconTerminalData>();
  const { beaconId, name, price, disabled } = props;
  const [amount, setAmount] = useState(1);

  const rangeLow = price.price_low;
  const rangeHigh = Math.max(price.price_high, price.price_low + 1);
  const span = rangeHigh - rangeLow;
  const changePct = price.previous_price
    ? Math.round(
        ((price.current_price - price.previous_price) / price.previous_price) *
          1000,
      ) / 10
    : 0;

  return (
    <Table.Row>
      <Table.Cell bold>{name}</Table.Cell>
      <Table.Cell>
        {price.current_price} cr
        <Box
          as="span"
          ml={1}
          color={changePct > 0 ? 'good' : changePct < 0 ? 'bad' : 'label'}
        >
          {changePct > 0 ? '+' : ''}
          {changePct}%
        </Box>
      </Table.Cell>
      <Table.Cell>
        <ProgressBar
          value={price.current_price}
          minValue={rangeLow}
          maxValue={rangeHigh}
          ranges={{
            bad: [-Infinity, rangeLow + span / 3],
            average: [rangeLow + span / 3, rangeHigh - span / 3],
            good: [rangeHigh - span / 3, Infinity],
          }}
        >
          {price.price_low} / {price.price_high}
        </ProgressBar>
      </Table.Cell>
      <Table.Cell>
        <NumberInput
          value={amount}
          minValue={1}
          width={3}
          step={1}
          onChange={(value) => setAmount(value)}
        />
        <Button
          ml={1}
          color="good"
          disabled={disabled}
          onClick={() =>
            act('buy', { commodity: price.key, amount, beacon_id: beaconId })
          }
        >
          Buy
        </Button>
        <Button
          ml={1}
          color="bad"
          disabled={disabled}
          onClick={() =>
            act('sell', { commodity: price.key, amount, beacon_id: beaconId })
          }
        >
          Sell
        </Button>
      </Table.Cell>
    </Table.Row>
  );
};
