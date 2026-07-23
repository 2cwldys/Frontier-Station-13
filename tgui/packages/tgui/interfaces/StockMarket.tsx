import { Box, Button, NoticeBox, NumberInput, Section, Table } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useState } from 'react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type CompanyRow = {
  company_id: number;
  ticker: string;
  name: string;
  current_price: number;
  previous_price: number;
  change_pct: number;
  market_cap: number;
  total_shares_outstanding: number;
  player_shares: number;
  shares_owned: number;
  avg_cost_basis: number;
};

type StockMarketData = {
  no_account?: BooleanLike;
  personal_balance?: number;
  total_market_cap?: number;
  companies?: CompanyRow[];
};

const formatCredits = (value: number) => {
  if (Math.abs(value) >= 1_000_000) {
    return `${(value / 1_000_000).toFixed(2)}M`;
  }
  if (Math.abs(value) >= 1_000) {
    return `${(value / 1_000).toFixed(1)}K`;
  }
  return `${value}`;
};

export const StockMarket = (props) => {
  const { data } = useBackend<StockMarketData>();

  if (data.no_account) {
    return (
      <NtosWindow width={480} height={300}>
        <NtosWindow.Content>
          <NoticeBox>
            You need a personal Idris account first -- print a replacement ID
            at any ID console to open one.
          </NoticeBox>
        </NtosWindow.Content>
      </NtosWindow>
    );
  }

  const companies = data.companies || [];

  return (
    <NtosWindow width={680} height={520}>
      <NtosWindow.Content scrollable>
        <Section title="Idris Market Exchange">
          <Box mb={0.5} bold>
            Personal Balance:{' '}
            <Box as="span" color="good">
              {data.personal_balance} credits
            </Box>
          </Box>
          <Box mb={1} bold>
            Total Market Cap:{' '}
            <Box as="span" color="label">
              {formatCredits(data.total_market_cap || 0)} credits
            </Box>{' '}
            <Box as="span" color="label" fontSize="0.9em">
              (combined net wealth of every investor across the exchange)
            </Box>
          </Box>
          <Table>
            <Table.Row header>
              <Table.Cell>Ticker</Table.Cell>
              <Table.Cell>Company</Table.Cell>
              <Table.Cell>Price</Table.Cell>
              <Table.Cell>Change</Table.Cell>
              <Table.Cell>Market Cap</Table.Cell>
              <Table.Cell>Owned</Table.Cell>
              <Table.Cell>Trade</Table.Cell>
            </Table.Row>
            {companies.map((company) => (
              <CompanyRowView key={company.company_id} company={company} />
            ))}
          </Table>
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};

const CompanyRowView = (props: { company: CompanyRow }) => {
  const { act } = useBackend<StockMarketData>();
  const { company: c } = props;
  const [amount, setAmount] = useState(1);
  const changeColor =
    c.change_pct > 0 ? 'good' : c.change_pct < 0 ? 'bad' : 'label';
  const floatPct = c.total_shares_outstanding
    ? ((c.player_shares / c.total_shares_outstanding) * 100).toFixed(3)
    : '0';

  return (
    <Table.Row>
      <Table.Cell bold>{c.ticker}</Table.Cell>
      <Table.Cell>
        {c.name}
        <Box color="label" fontSize="0.85em">
          {formatCredits(c.total_shares_outstanding)} shares outstanding --
          all investors hold {floatPct}% of float
        </Box>
      </Table.Cell>
      <Table.Cell>{c.current_price} cr</Table.Cell>
      <Table.Cell color={changeColor}>
        {c.change_pct > 0 ? '+' : ''}
        {c.change_pct}%
      </Table.Cell>
      <Table.Cell>{formatCredits(c.market_cap)} cr</Table.Cell>
      <Table.Cell>
        {c.shares_owned}
        {c.shares_owned > 0 ? ` (avg ${c.avg_cost_basis} cr)` : ''}
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
          onClick={() => act('buy', { company_id: c.company_id, amount })}
        >
          Buy
        </Button>
        <Button
          ml={1}
          color="bad"
          disabled={c.shares_owned < amount}
          onClick={() => act('sell', { company_id: c.company_id, amount })}
        >
          Sell
        </Button>
      </Table.Cell>
    </Table.Row>
  );
};
