import {
  Box,
  Button,
  Dropdown,
  Icon,
  LabeledList,
  Section,
  Stack,
  Table,
  Tabs,
  Tooltip,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useBackend, useLocalState } from '../backend';
import { NtosWindow } from '../layouts';
import { sanitizeText } from '../sanitize';
import { SearchBar } from './common/SearchBar';

type TelepadChoice = {
  ref: string;
  area_name: string;
};

export type CargoData = {
  faction_network: string | null;
  faction_name: string | null;
  faction_balance: number | null;
  is_personal: BooleanLike;
  personal_owner_name: string | null;
  personal_balance: number | null;
  personal_allowed_category: string | null;
  personal_cargo_category_cooldown_remaining: number;
  is_crew: BooleanLike;
  crew_ship_name: string | null;
  crew_balance: number | null;
  telepad_choices: TelepadChoice[];
  selected_telepad_ref: string | null;
  username: string;
  order_items: Item[];
  order_value: number;
  order_item_count: number;
  cargo_categories: Category[];
  selected_category: string;
  category_items: Item[];

  tracking_id: number;
  tracking_code: number;
  tracking_status: string;
  tracked_order: Order;
  tracked_order_report: string;

  page: string;
  status_message: string;
  handling_fee: number;
  crate_fee: number;
};

type Item = {
  name: string;
  description: string;
  amount: number;
  price: number;
  price_adjusted: number;
  id: number;
  supplier: string;
  supplier_data: Supplier;
  access: string;
};

type Supplier = {
  short_name: string;
  name: string;
  description: string;
  tag_line: string;
  shuttle_time: number;
  shuttle_price: number;
  available: BooleanLike;
  price_modifier: number;
};

type Category = {
  name: string;
  display_name: string;
  description: string;
  icon: string;
  price_modifier: number;
};

type Order = {
  order_id: number;
  tracking_code: number;
  price: number;
  price_customer: number;
  price_cargo: number;
  status: string;
  status_pretty: string;
  status_payment: string;
  ordered_by: string;
  authorized_by: string;
  received_by: string;
  paid_by: string;
  needs_payment: BooleanLike;
  time_submitted: string;
  time_approved: string;
  time_shipped: string;
  time_delivered: string;
  time_paid: string;
  items: Item[];
  shipment_cost: number;
  reason: string;
};

export const CargoOrder = (props) => {
  const { act, data } = useBackend<CargoData>();

  return (
    <NtosWindow resizable width={800} height={800}>
      <NtosWindow.Content scrollable>
        <Tabs fluid>
          <Tabs.Tab
            onClick={() => act('page', { page: 'main' })}
            selected={data.page === 'main'}
          >
            Main
          </Tabs.Tab>
          <Tabs.Tab
            onClick={() => act('page', { page: 'tracking' })}
            selected={data.page === 'tracking'}
          >
            Tracking
          </Tabs.Tab>
        </Tabs>
        {data.page === 'main' ? <MainPage /> : <TrackingPage />}
      </NtosWindow.Content>
    </NtosWindow>
  );
};

export const MainPage = (props) => {
  const { act, data } = useBackend<CargoData>();
  const [details, setDetails] = useLocalState<boolean>('details', false);
  const [searchTerm, setSearchTerm] = useLocalState<string>(`searchTerm`, ``);
  const needsTelepadPick =
    data.telepad_choices.length > 1 && !data.selected_telepad_ref;

  return (
    <Stack vertical>
      {data.faction_network && (
        <Box mb={1} bold>
          {data.faction_name ?? data.faction_network} Balance:{' '}
          <Box as="span" color={data.faction_balance !== null ? 'good' : 'label'}>
            {data.faction_balance !== null ? `${data.faction_balance} credits` : 'N/A'}
          </Box>
        </Box>
      )}
      {!!data.is_personal && (
        <Box mb={1} bold>
          Personal Balance:{' '}
          <Box as="span" color={data.personal_balance !== null ? 'good' : 'label'}>
            {data.personal_balance !== null ? `${data.personal_balance} credits` : 'N/A'}
          </Box>
          <Box color="label" mt={0.5}>
            Orders from this console are paid from your personal account, not
            a faction.
          </Box>
          {data.personal_cargo_category_cooldown_remaining > 0 ? (
            <Box color="label" mt={0.5}>
              Cargo specialization:{' '}
              {data.cargo_categories.find(
                (c) => c.name === data.personal_allowed_category,
              )?.display_name || 'None'}{' '}
              (locked for{' '}
              {Math.ceil(
                data.personal_cargo_category_cooldown_remaining / 86400,
              )}{' '}
              more day(s))
            </Box>
          ) : (
            <Dropdown
              mt={0.5}
              width="100%"
              selected={
                data.cargo_categories.find(
                  (c) => c.name === data.personal_allowed_category,
                )?.display_name || 'Choose your cargo specialization'
              }
              options={data.cargo_categories.map((c) => c.display_name)}
              onSelected={(display_name) =>
                act('set_personal_cargo_category', { category: display_name })
              }
            />
          )}
        </Box>
      )}
      {!!data.is_crew && (
        <Box mb={1} bold>
          {data.crew_ship_name ?? 'Ship'} Crew Balance:{' '}
          <Box as="span" color={data.crew_balance !== null ? 'good' : 'label'}>
            {data.crew_balance !== null ? `${data.crew_balance} credits` : 'N/A'}
          </Box>
          <Box color="label" mt={0.5}>
            Orders from this console are billed to the ship owner's account,
            not yours.
          </Box>
        </Box>
      )}
      {data.telepad_choices.length > 1 && (
        <Dropdown
          mb={1}
          width="100%"
          selected={
            data.telepad_choices.find(
              (t) => t.ref === data.selected_telepad_ref,
            )?.area_name || 'Select a delivery telepad'
          }
          options={data.telepad_choices.map((t) => t.area_name)}
          onSelected={(area_name) => {
            const choice = data.telepad_choices.find(
              (t) => t.area_name === area_name,
            );
            if (choice) {
              act('select_telepad', { select_telepad: choice.ref });
            }
          }}
        />
      )}
      <Section title={`Welcome, ${data.username}`}>
        <Stack vertical>
          <Stack.Item fontSize={1.4} bold>
            Your Basket
          </Stack.Item>
          <Stack.Item>
            <LabeledList>
              <LabeledList.Item label="Items">
                {data.order_item_count}
              </LabeledList.Item>
              <LabeledList.Item label="Price">
                {data.order_value.toFixed(2)}₵
              </LabeledList.Item>
              {data.status_message && (
                <LabeledList.Item label="Status">
                  {data.status_message}
                </LabeledList.Item>
              )}
            </LabeledList>
          </Stack.Item>
          <Stack.Item>
            <Button
              content="Details"
              icon="list"
              onClick={() => setDetails(!details)}
            />
            <Button
              content="Clear"
              color="red"
              icon="stop"
              onClick={() => act('clear_order')}
            />
            <Button
              content="Submit Order"
              icon="check"
              disabled={needsTelepadPick}
              tooltip={
                needsTelepadPick
                  ? 'Select a delivery telepad above first.'
                  : undefined
              }
              onClick={() => act('submit_order')}
            />
          </Stack.Item>
          {details && <ShowDetails />}
        </Stack>
      </Section>
      <Section
        title="Catalog"
        buttons={
          <SearchBar
            autoFocus
            placeholder="Search by name"
            query={searchTerm}
            onSearch={(value) => {
              setSearchTerm(value);
            }}
          />
        }
      />
      <Stack>
        {/* Left Side: Tabs Section */}
        <Stack.Item width={'175px'}>
          <Tabs vertical>
            {data.cargo_categories.map((category) => (
              <Tabs.Tab
                key={category.name}
                selected={data.selected_category === category.name}
                onClick={() =>
                  act('select_category', { select_category: category.name })
                }
              >
                <Icon name={category.icon} /> {category.display_name}
              </Tabs.Tab>
            ))}
          </Tabs>
        </Stack.Item>

        {/* Right Side: Content Section */}
        <Stack.Item grow>
          {data.category_items
            .filter(
              (c) =>
                c.name?.toLowerCase().indexOf(searchTerm.toLowerCase()) > -1,
            )
            .map((item) => (
              <Section
                title={item.name}
                key={item.name}
                buttons={
                  <Button
                    content={`${item.price_adjusted.toFixed(2)}₵`}
                    disabled={
                      !item.supplier_data.available && item.price_adjusted <= 0
                    }
                    tooltip="Add to Basket"
                    icon="shopping-basket"
                    onClick={() =>
                      act('add_item', { add_item: item.name.toString() })
                    }
                  />
                }
              >
                <Stack vertical>
                  <Stack.Item>{item.description}</Stack.Item>
                  <Stack.Item>
                    <LabeledList>
                      <Tooltip content={item.supplier_data.description}>
                        <LabeledList.Item label="Shipped By">
                          {item.supplier_data.name}
                        </LabeledList.Item>
                      </Tooltip>
                      <LabeledList.Item label="Required Access">
                        {item.access !== 'none' ? (
                          <Tooltip content="This item has restricted access.">
                            <Icon name="lock" /> {item.access}
                          </Tooltip>
                        ) : (
                          <>None</>
                        )}
                      </LabeledList.Item>
                    </LabeledList>
                  </Stack.Item>
                </Stack>
              </Section>
            ))}
        </Stack.Item>
      </Stack>
    </Stack>
  );
};

export const ShowDetails = (props) => {
  const { act, data } = useBackend<CargoData>();

  return (
    <Section title="Details">
      <Table>
        <Table.Row header>
          <Table.Cell>Name</Table.Cell>
          <Table.Cell>Price</Table.Cell>
        </Table.Row>
        <Table.Row>
          <Table.Cell>Handling Fee</Table.Cell>
          <Table.Cell>{data.handling_fee.toFixed(2)}₵</Table.Cell>
        </Table.Row>
        <Table.Row>
          <Table.Cell>Crate Fee</Table.Cell>
          <Table.Cell>{data.crate_fee.toFixed(2)}₵</Table.Cell>
        </Table.Row>
        {data.order_items.map((item) => (
          <Table.Row key={item.name}>
            <Table.Cell>{item.name}</Table.Cell>
            <Table.Cell>{item.price.toFixed(2)}₵</Table.Cell>
          </Table.Row>
        ))}
      </Table>
    </Section>
  );
};

export const TrackingPage = (props) => {
  const { act, data } = useBackend<CargoData>();

  return (
    <Section title="Tracking">
      <LabeledList>
        {data.tracking_status && (
          <LabeledList.Item label="Tracking Status">
            {data.tracking_status}
          </LabeledList.Item>
        )}
        <LabeledList.Item label="Tracking Code">
          <Button
            content={data.tracking_code}
            icon="edit"
            onClick={() => act('trackingcode')}
          />
        </LabeledList.Item>
        <LabeledList.Item label="Order ID">
          <Button
            content={data.tracking_id}
            icon="edit"
            onClick={() => act('trackingid')}
          />
        </LabeledList.Item>
      </LabeledList>
      {data.tracking_status === 'Success' && <ShowTrackingStatus />}
    </Section>
  );
};

export const ShowTrackingStatus = (props) => {
  const { act, data } = useBackend<CargoData>();
  const contentHtml = { __html: sanitizeText(data.tracked_order_report) };

  return (
    <Section title={`Tracking Information`}>
      {/** biome-ignore lint/security/noDangerouslySetInnerHtml: Is sanitized by DOMPurify. */}
      <Box dangerouslySetInnerHTML={contentHtml} />
    </Section>
  );
};
