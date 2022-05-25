%
foo do
end
-
foo {}
%
foo do
  # comment
end
%
foo do # comment
end
%
foo :bar do
  baz
end
%
sig do
  override.params(contacts: Contact::ActiveRecord_Relation).returns(
    Customer::ActiveRecord_Relation
  )
end
-
sig do
  override
    .params(contacts: Contact::ActiveRecord_Relation)
    .returns(Customer::ActiveRecord_Relation)
end
