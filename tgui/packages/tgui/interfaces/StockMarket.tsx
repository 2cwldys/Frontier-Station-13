import {
  Box,
  Button,
  NoticeBox,
  NumberInput,
  ProgressBar,
  Section,
  Table,
  Tabs,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { useState } from 'react';
import { useBackend } from '../backend';
import { NtosWindow } from '../layouts';

type CompanyRow = {
  company_id: number;
  ticker: string;
  name: string;
  faction_uid: string | null;
  faction_name: string | null;
  current_price: number;
  previous_price: number;
  price_high: number;
  price_low: number;
  change_pct: number;
  market_cap: number;
  total_shares_outstanding: number;
  player_shares: number;
  shares_owned: number;
  avg_cost_basis: number;
};

type TradeLogRow = {
  ticker: string;
  name: string;
  is_buy: BooleanLike;
  shares: number;
  price_per_share: number;
  total: number;
  traded_at: string;
};

type StockMarketData = {
  no_account?: BooleanLike;
  personal_balance?: number;
  personal_portfolio_value?: number;
  total_market_cap?: number;
  companies?: CompanyRow[];
  trade_history?: TradeLogRow[];
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
  const [tab, setTab] = useState('Market');

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
  const tradeHistory = data.trade_history || [];
  const aiCompanies = companies.filter((c) => !c.faction_uid);
  const factionCompanies = companies.filter((c) => c.faction_uid);

  return (
    <NtosWindow width={780} height={580}>
      <NtosWindow.Content scrollable>
        <Tabs>
          <Tabs.Tab selected={tab === 'Market'} onClick={() => setTab('Market')}>
            Market
          </Tabs.Tab>
          <Tabs.Tab
            selected={tab === 'Portfolio'}
            onClick={() => setTab('Portfolio')}
          >
            Portfolio
          </Tabs.Tab>
        </Tabs>
        {tab === 'Market' && (
          <Section title="Idris Market Exchange">
            <Box mb={0.5} bold>
              Personal Balance:{' '}
              <Box as="span" color="good">
                {data.personal_balance} credits
              </Box>
            </Box>
            <Box mb={0.5} bold>
              Your Portfolio Value:{' '}
              <Box as="span" color="good">
                {formatCredits(data.personal_portfolio_value || 0)} credits
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
          </Section>
        )}
        {tab === 'Market' && (
          <Section title="AI-Simulated Companies">
            <Table>
              <Table.Row header>
                <Table.Cell>Ticker</Table.Cell>
                <Table.Cell>Company</Table.Cell>
                <Table.Cell>Price</Table.Cell>
                <Table.Cell>Change</Table.Cell>
                <Table.Cell width="18%">Range (Low / High)</Table.Cell>
                <Table.Cell>Market Cap</Table.Cell>
                <Table.Cell>Owned</Table.Cell>
                <Table.Cell>Trade</Table.Cell>
              </Table.Row>
              {aiCompanies.map((company) => (
                <CompanyRowView key={company.company_id} company={company} />
              ))}
            </Table>
          </Section>
        )}
        {tab === 'Market' && factionCompanies.length > 0 && (
          <Section title="Player-Owned Companies">
            <Table>
              <Table.Row header>
                <Table.Cell>Ticker</Table.Cell>
                <Table.Cell>Company</Table.Cell>
                <Table.Cell>Faction</Table.Cell>
                <Table.Cell>Price</Table.Cell>
                <Table.Cell>Change</Table.Cell>
                <Table.Cell width="18%">Range (Low / High)</Table.Cell>
                <Table.Cell>Market Cap</Table.Cell>
                <Table.Cell>Owned</Table.Cell>
                <Table.Cell>Trade</Table.Cell>
              </Table.Row>
              {factionCompanies.map((company) => (
                <CompanyRowView
                  key={company.company_id}
                  company={company}
                  showFaction
                />
              ))}
            </Table>
          </Section>
        )}
        {tab === 'Portfolio' && (
          <PortfolioTab companies={companies} tradeHistory={tradeHistory} />
        )}
      </NtosWindow.Content>
    </NtosWindow>
  );
};

const CompanyRowView = (props: {
  company: CompanyRow;
  showFaction?: boolean;
}) => {
  const { act } = useBackend<StockMarketData>();
  const { company: c, showFaction } = props;
  const [amount, setAmount] = useState(1);
  const changeColor =
    c.change_pct > 0 ? 'good' : c.change_pct < 0 ? 'bad' : 'label';
  const floatPct = c.total_shares_outstanding
    ? ((c.player_shares / c.total_shares_outstanding) * 100).toFixed(3)
    : '0';

  // Guard against a degenerate (no movement yet) range -- pad by 1 so the
  // ProgressBar always has a real span instead of minValue === maxValue.
  const rangeLow = c.price_low;
  const rangeHigh = Math.max(c.price_high, c.price_low + 1);
  const span = rangeHigh - rangeLow;

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
      {showFaction && <Table.Cell>{c.faction_name}</Table.Cell>}
      <Table.Cell>{c.current_price} cr</Table.Cell>
      <Table.Cell color={changeColor}>
        {c.change_pct > 0 ? '+' : ''}
        {c.change_pct}%
      </Table.Cell>
      <Table.Cell>
        <ProgressBar
          value={c.current_price}
          minValue={rangeLow}
          maxValue={rangeHigh}
          ranges={{
            bad: [-Infinity, rangeLow + span / 3],
            average: [rangeLow + span / 3, rangeHigh - span / 3],
            good: [rangeHigh - span / 3, Infinity],
          }}
        >
          {c.price_low} / {c.price_high}
        </ProgressBar>
      </Table.Cell>
      <Table.Cell>{formatCredits(c.market_cap)} cr</Table.Cell>
      <Table.Cell>{c.shares_owned}</Table.Cell>
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
        <Button
          ml={1}
          disabled={c.shares_owned < amount}
          onClick={() => act('give', { company_id: c.company_id, amount })}
        >
          Give
        </Button>
      </Table.Cell>
    </Table.Row>
  );
};

const PortfolioTab = (props: {
  companies: CompanyRow[];
  tradeHistory: TradeLogRow[];
}) => {
  const { companies, tradeHistory } = props;
  const held = companies.filter((c) => c.shares_owned > 0);

  return (
    <>
      <Section title="Current Holdings">
        <Table>
          <Table.Row header>
            <Table.Cell>Ticker</Table.Cell>
            <Table.Cell>Shares</Table.Cell>
            <Table.Cell>Purchase Price</Table.Cell>
            <Table.Cell>Current Price</Table.Cell>
            <Table.Cell>Current Value</Table.Cell>
            <Table.Cell>Profit / Loss</Table.Cell>
          </Table.Row>
          {held.length ? (
            held.map((c) => {
              const value = c.shares_owned * c.current_price;
              const cost = c.shares_owned * c.avg_cost_basis;
              const pl = value - cost;
              return (
                <Table.Row key={c.company_id}>
                  <Table.Cell bold>{c.ticker}</Table.Cell>
                  <Table.Cell>{c.shares_owned}</Table.Cell>
                  <Table.Cell>{c.avg_cost_basis} cr</Table.Cell>
                  <Table.Cell>{c.current_price} cr</Table.Cell>
                  <Table.Cell>{value} cr</Table.Cell>
                  <Table.Cell color={pl > 0 ? 'good' : pl < 0 ? 'bad' : 'label'}>
                    {pl > 0 ? '+' : ''}
                    {pl} cr
                  </Table.Cell>
                </Table.Row>
              );
            })
          ) : (
            <Table.Row>
              <Table.Cell colSpan={6}>You don't own any shares yet.</Table.Cell>
            </Table.Row>
          )}
        </Table>
      </Section>
      <Section title="Trade History">
        <Table>
          <Table.Row header>
            <Table.Cell>Date</Table.Cell>
            <Table.Cell>Ticker</Table.Cell>
            <Table.Cell>Action</Table.Cell>
            <Table.Cell>Shares</Table.Cell>
            <Table.Cell>Price/Share</Table.Cell>
            <Table.Cell>Total</Table.Cell>
          </Table.Row>
          {tradeHistory.length ? (
            tradeHistory.map((t, index) => (
              // eslint-disable-next-line react/no-array-index-key
              <Table.Row key={index}>
                <Table.Cell>{t.traded_at}</Table.Cell>
                <Table.Cell bold>{t.ticker}</Table.Cell>
                <Table.Cell color={t.is_buy ? 'good' : 'bad'}>
                  {t.is_buy ? 'Buy' : 'Sell'}
                </Table.Cell>
                <Table.Cell>{t.shares}</Table.Cell>
                <Table.Cell>{t.price_per_share} cr</Table.Cell>
                <Table.Cell>{t.total} cr</Table.Cell>
              </Table.Row>
            ))
          ) : (
            <Table.Row>
              <Table.Cell colSpan={6}>No trades yet.</Table.Cell>
            </Table.Row>
          )}
        </Table>
      </Section>
    </>
  );
};
